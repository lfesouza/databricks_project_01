# silver.vendas: uma linha por venda, com receita e marcações de qualidade.
#
# Por que estas regras:
# - Materialized view com leitura batch: a bronze é sobrescrita a cada ingestão.
# - Remover duplicatas por id_venda: uma venda repetida seria receita contada duas vezes.
# - preco_unitario e receita em DECIMAL(10,2): dinheiro sem erro de ponto flutuante. A receita é
#   calculada sobre o preço já convertido, para bater centavo a centavo com quantidade × preço.
# - data, hora e dia da semana ficam prontos para as análises de sazonalidade. dia_semana é
#   derivado do número (1 = domingo ... 7 = sábado) para não depender do idioma da sessão.
# - Vendas de produto não cadastrado e vendas anteriores ao cadastro do produto são problemas
#   conhecidos da origem. Elas são MARCADAS (produto_cadastrado, venda_antes_do_cadastro) e medidas
#   com expect (warn), NUNCA descartadas: apagar vendas mudaria a receita.
# - Fail só para o que nunca pode acontecer: campos obrigatórios vazios, quantidade ou preço
#   zero/negativo, ou canal desconhecido indicam dado corrompido; melhor parar do que publicar.

from pyspark import pipelines as dp
from pyspark.sql import functions as F

DIAS_SEMANA = {1: "Domingo", 2: "Segunda", 3: "Terça", 4: "Quarta", 5: "Quinta", 6: "Sexta", 7: "Sábado"}


def nome_dia_semana(numero):
    mapa = F.create_map(*[F.lit(v) for par in DIAS_SEMANA.items() for v in par])
    return mapa[numero]


@dp.materialized_view(
    name="silver.vendas",
    comment="Vendas deduplicadas, com receita, calendário e marcações de qualidade do produto.",
)
@dp.expect_all_or_fail(
    {
        "id_venda_preenchido": "id_venda IS NOT NULL",
        "data_venda_preenchida": "data_venda IS NOT NULL",
        "id_cliente_preenchido": "id_cliente IS NOT NULL",
        "id_produto_preenchido": "id_produto IS NOT NULL",
        "quantidade_preenchida": "quantidade IS NOT NULL",
        "preco_unitario_preenchido": "preco_unitario IS NOT NULL",
        "quantidade_positiva": "quantidade > 0",
        "preco_unitario_positivo": "preco_unitario > 0",
        "canal_venda_valido": "canal_venda IN ('ecommerce', 'loja_fisica')",
    }
)
@dp.expect("produto_cadastrado", "produto_cadastrado")
@dp.expect("venda_depois_do_cadastro", "NOT venda_antes_do_cadastro")
def vendas():
    produtos = spark.read.table("silver.produtos").select(
        "id_produto", "data_criacao", F.lit(True).alias("_produto_existe")
    )
    preco_unitario = F.col("preco_unitario").cast("decimal(10,2)")
    dia_semana_num = F.dayofweek("data_venda")
    return (
        spark.read.table("bronze.vendas")
        .dropDuplicates(["id_venda"])
        .join(produtos, "id_produto", "left")
        .select(
            "id_venda",
            "data_venda",
            F.to_date("data_venda").alias("data"),
            F.hour("data_venda").alias("hora"),
            dia_semana_num.alias("dia_semana_num"),
            nome_dia_semana(dia_semana_num).alias("dia_semana"),
            "id_cliente",
            "id_produto",
            "canal_venda",
            "quantidade",
            preco_unitario.alias("preco_unitario"),
            (F.col("quantidade") * preco_unitario).cast("decimal(10,2)").alias("receita"),
            F.col("_produto_existe").isNotNull().alias("produto_cadastrado"),
            F.coalesce(F.col("data_venda") < F.col("data_criacao"), F.lit(False)).alias(
                "venda_antes_do_cadastro"
            ),
        )
    )
