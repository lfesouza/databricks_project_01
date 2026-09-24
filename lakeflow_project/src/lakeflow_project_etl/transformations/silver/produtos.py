# silver.produtos: cadastro de produtos limpo, uma linha por id_produto.
#
# Por que estas regras:
# - Materialized view com leitura batch: a bronze é sobrescrita a cada ingestão, então uma
#   streaming table (append-only) quebraria ou duplicaria dados. Recalcular do zero é o correto.
# - Remover duplicatas por id_produto: vendas e preços de concorrentes fazem join por essa chave;
#   um produto repetido multiplicaria as linhas de venda e inflaria a receita.
# - trim em nome_produto: espaços sobrando geram "produtos diferentes" em agrupamentos e filtros.
# - preco_atual em DECIMAL(10,2): dinheiro não pode ter erro de arredondamento de ponto flutuante.
# - faixa_preco: segmentação usada nas análises (PREMIUM > 1000, MEDIO > 500, senão BASICO).
# - Fail só para o que nunca pode acontecer: produto sem id não pode ser ligado a nada, e preço
#   zero ou negativo indica cadastro corrompido; nesses casos é melhor parar a atualização.

from pyspark import pipelines as dp
from pyspark.sql import functions as F


@dp.materialized_view(
    name="silver.produtos",
    comment="Produtos deduplicados por id_produto, com preço em DECIMAL(10,2) e faixa de preço.",
)
@dp.expect_all_or_fail(
    {
        "id_produto_preenchido": "id_produto IS NOT NULL",
        "preco_atual_positivo": "preco_atual > 0",
    }
)
def produtos():
    preco_atual = F.col("preco_atual").cast("decimal(10,2)")
    return (
        spark.read.table("bronze.produtos")
        .dropDuplicates(["id_produto"])
        .select(
            "id_produto",
            F.trim("nome_produto").alias("nome_produto"),
            "categoria",
            "marca",
            preco_atual.alias("preco_atual"),
            F.when(preco_atual > 1000, "PREMIUM")
            .when(preco_atual > 500, "MEDIO")
            .otherwise("BASICO")
            .alias("faixa_preco"),
            "data_criacao",
        )
    )
