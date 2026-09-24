# silver.preco_competidores: um preço por produto e concorrente, com marcação de preço suspeito.
#
# Por que estas regras:
# - Materialized view com leitura batch: a bronze é sobrescrita a cada ingestão.
# - Remover duplicatas por (id_produto, nome_concorrente): cada concorrente tem um preço por
#   produto; repetições distorceriam médias e comparações de preço.
# - preco_concorrente em DECIMAL(10,2): dinheiro sem erro de ponto flutuante.
# - data_coleta chega como texto; convertida para timestamp para permitir filtros e ordenação.
# - preco_suspeito: um concorrente cobrando menos de 60% do nosso preco_atual é provavelmente
#   erro de coleta (unidade, promoção relâmpago, produto errado). A linha é MARCADA e medida com
#   expect (warn), não descartada: quem consome decide se usa ou não.
# - Fail: preço sem produto não pode ser comparado a nada, e preço zero ou negativo é inválido.

from pyspark import pipelines as dp
from pyspark.sql import functions as F


@dp.materialized_view(
    name="silver.preco_competidores",
    comment="Preços de concorrentes deduplicados, com data de coleta e marcação de preço suspeito.",
)
@dp.expect_all_or_fail(
    {
        "id_produto_preenchido": "id_produto IS NOT NULL",
        "preco_concorrente_positivo": "preco_concorrente > 0",
    }
)
@dp.expect("preco_plausivel", "NOT preco_suspeito")
def preco_competidores():
    produtos = spark.read.table("silver.produtos").select("id_produto", "preco_atual")
    return (
        spark.read.table("bronze.preco_competidores")
        .dropDuplicates(["id_produto", "nome_concorrente"])
        .withColumn("preco_concorrente", F.col("preco_concorrente").cast("decimal(10,2)"))
        .withColumn("data_coleta", F.to_timestamp("data_coleta", "yyyy-MM-dd HH:mm:ss"))
        .join(produtos, "id_produto", "left")
        .withColumn(
            "preco_suspeito",
            F.coalesce(F.col("preco_concorrente") < F.col("preco_atual") * 0.6, F.lit(False)),
        )
        .select("id_produto", "nome_concorrente", "preco_concorrente", "data_coleta", "preco_suspeito")
    )
