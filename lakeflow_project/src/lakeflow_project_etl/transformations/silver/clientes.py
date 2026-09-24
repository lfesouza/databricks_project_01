# silver.clientes: cadastro de clientes limpo, uma linha por id_cliente, com região do IBGE.
#
# Por que estas regras:
# - Materialized view com leitura batch: a bronze é sobrescrita a cada ingestão.
# - Remover duplicatas por id_cliente: um cliente repetido duplicaria as vendas no join.
# - nome_original guarda o nome como veio da origem, para auditoria; nome_cliente é a versão
#   padronizada, sem pronome de tratamento (Sr., Sra., Srta., Dr., Dra.) e em formato título.
#   O pronome não faz parte do nome e atrapalha buscas, ordenação e deduplicação.
# - No formato título, as partículas (da, de, do, das, dos, e) ficam em minúsculas, como se
#   escreve nome próprio em português ("Henrique da Conceição", e não "Henrique Da Conceição").
# - estado (UF) em maiúsculas para casar com o mapeamento de estados.
# - A bronze não tem tabela de estados, então o mapeamento das 27 UFs (26 estados + DF) com as
#   5 regiões do IBGE fica fixo neste arquivo: é um dado de referência que praticamente não muda.
# - Fail: cliente sem id não pode ser ligado a vendas, e região vazia significa UF desconhecida,
#   o que invalidaria as análises regionais.

from pyspark import pipelines as dp
from pyspark.sql import functions as F

# (uf, nome_estado, regiao) conforme a divisão regional do IBGE.
ESTADOS = [
    ("AC", "Acre", "Norte"),
    ("AP", "Amapá", "Norte"),
    ("AM", "Amazonas", "Norte"),
    ("PA", "Pará", "Norte"),
    ("RO", "Rondônia", "Norte"),
    ("RR", "Roraima", "Norte"),
    ("TO", "Tocantins", "Norte"),
    ("AL", "Alagoas", "Nordeste"),
    ("BA", "Bahia", "Nordeste"),
    ("CE", "Ceará", "Nordeste"),
    ("MA", "Maranhão", "Nordeste"),
    ("PB", "Paraíba", "Nordeste"),
    ("PE", "Pernambuco", "Nordeste"),
    ("PI", "Piauí", "Nordeste"),
    ("RN", "Rio Grande do Norte", "Nordeste"),
    ("SE", "Sergipe", "Nordeste"),
    ("DF", "Distrito Federal", "Centro-Oeste"),
    ("GO", "Goiás", "Centro-Oeste"),
    ("MT", "Mato Grosso", "Centro-Oeste"),
    ("MS", "Mato Grosso do Sul", "Centro-Oeste"),
    ("ES", "Espírito Santo", "Sudeste"),
    ("MG", "Minas Gerais", "Sudeste"),
    ("RJ", "Rio de Janeiro", "Sudeste"),
    ("SP", "São Paulo", "Sudeste"),
    ("PR", "Paraná", "Sul"),
    ("RS", "Rio Grande do Sul", "Sul"),
    ("SC", "Santa Catarina", "Sul"),
]

# Pronome de tratamento no início do nome, seguido de ponto e espaço.
PRONOME_TRATAMENTO = r"(?i)^(sr|sra|srta|dr|dra)\.\s+"

PARTICULAS = ["da", "de", "do", "das", "dos", "e"]


def formato_titulo(nome):
    """Formato título mantendo as partículas dos nomes em minúsculas."""
    nome = F.initcap(F.lower(nome))
    for particula in PARTICULAS:
        nome = F.regexp_replace(nome, rf"(?<= ){particula.capitalize()}(?= )", particula)
    return nome


@dp.materialized_view(
    name="silver.clientes",
    comment="Clientes deduplicados, com nome sem pronome de tratamento, UF, estado e região.",
)
@dp.expect_all_or_fail(
    {
        "id_cliente_preenchido": "id_cliente IS NOT NULL",
        "regiao_preenchida": "regiao IS NOT NULL",
    }
)
def clientes():
    estados = spark.createDataFrame(ESTADOS, "uf string, nome_estado string, regiao string")
    nome_sem_pronome = F.regexp_replace(F.trim("nome_cliente"), PRONOME_TRATAMENTO, "")
    return (
        spark.read.table("bronze.clientes")
        .dropDuplicates(["id_cliente"])
        .withColumn("estado", F.upper(F.trim("estado")))
        .join(estados, F.col("estado") == estados.uf, "left")
        .select(
            "id_cliente",
            formato_titulo(nome_sem_pronome).alias("nome_cliente"),
            F.col("nome_cliente").alias("nome_original"),
            "estado",
            "nome_estado",
            "regiao",
            "pais",
            "data_cadastro",
        )
    )
