# Databricks notebook source
# Testes de qualidade da camada silver do e-commerce.
#
# Por que este notebook existe:
# - As expectations do pipeline medem problemas linha a linha; aqui validamos regras que olham a
#   tabela inteira (chave única, proporção de vendas problemáticas) depois que o pipeline publica.
# - Cada teste é uma consulta que CONTA linhas com problema. Zero = passou. Assim o resultado é
#   comparável entre execuções e fácil de ler na tabela final.
# - Se algum teste encontrar problema, o notebook falha com AssertionError, o que falha o Job
#   "Pipeline E-commerce" e avisa quem acompanha.

# COMMAND ----------

dbutils.widgets.text("catalogo", "ecommerce")
catalogo = dbutils.widgets.get("catalogo")
spark.sql(f"USE CATALOG {catalogo}")

# COMMAND ----------

TESTES = [
    (
        "silver.produtos: id_produto único",
        "SELECT count(*) - count(DISTINCT id_produto) FROM silver.produtos",
    ),
    (
        "silver.clientes: id_cliente único",
        "SELECT count(*) - count(DISTINCT id_cliente) FROM silver.clientes",
    ),
    (
        "silver.preco_competidores: (id_produto, nome_concorrente) único",
        "SELECT count(*) - count(DISTINCT id_produto, nome_concorrente) FROM silver.preco_competidores",
    ),
    (
        "silver.vendas: id_venda único",
        "SELECT count(*) - count(DISTINCT id_venda) FROM silver.vendas",
    ),
    (
        "silver.vendas: receita = quantidade × preco_unitario",
        """SELECT count(*) FROM silver.vendas
           WHERE receita IS DISTINCT FROM CAST(quantidade * preco_unitario AS DECIMAL(10,2))""",
    ),
    (
        # Conta 1 quando as vendas de produto não cadastrado chegam a 1% do total.
        "silver.vendas: produto não cadastrado abaixo de 1% das vendas",
        """SELECT CASE WHEN count_if(NOT produto_cadastrado) >= 0.01 * count(*) THEN 1 ELSE 0 END
           FROM silver.vendas""",
    ),
    # gold.clientes_segmentacao
    (
        # Conta 1 quando a receita da gold difere da silver: nenhuma venda pode se perder no join.
        "gold.clientes_segmentacao: receita total igual à de silver.vendas",
        """SELECT CASE WHEN (SELECT sum(receita) FROM gold.clientes_segmentacao)
                            = (SELECT sum(receita) FROM silver.vendas) THEN 0 ELSE 1 END""",
    ),
    (
        "gold.clientes_segmentacao: id_cliente único",
        "SELECT count(*) - count(DISTINCT id_cliente) FROM gold.clientes_segmentacao",
    ),
    (
        "gold.clientes_segmentacao: segmento só VIP, TOP_TIER ou REGULAR",
        """SELECT count(*) FROM gold.clientes_segmentacao
           WHERE segmento_cliente IS NULL OR segmento_cliente NOT IN ('VIP', 'TOP_TIER', 'REGULAR')""",
    ),
    (
        "gold.clientes_segmentacao: nenhum VIP com receita abaixo de 22.000",
        "SELECT count(*) FROM gold.clientes_segmentacao WHERE segmento_cliente = 'VIP' AND receita < 22000",
    ),
    # gold.vendas_temporais, gold.vendas_produtos, gold.vendas_detalhadas
    *[
        (
            # Conta 1 quando a receita da gold difere da silver: nenhuma venda pode se perder.
            f"gold.{tabela}: receita total igual à de silver.vendas",
            f"""SELECT CASE WHEN (SELECT sum(receita) FROM gold.{tabela})
                                 = (SELECT sum(receita) FROM silver.vendas) THEN 0 ELSE 1 END""",
        )
        for tabela in ["vendas_temporais", "vendas_produtos", "vendas_detalhadas"]
    ],
    (
        # Diferença absoluta de linhas: venda perdida ou duplicada nos joins.
        "gold.vendas_detalhadas: mesmo número de linhas de silver.vendas",
        "SELECT abs((SELECT count(*) FROM gold.vendas_detalhadas) - (SELECT count(*) FROM silver.vendas))",
    ),
    (
        "gold.vendas_detalhadas: id_venda único",
        "SELECT count(*) - count(DISTINCT id_venda) FROM gold.vendas_detalhadas",
    ),
    (
        "gold.vendas_detalhadas: toda venda com segmento e região",
        "SELECT count(*) FROM gold.vendas_detalhadas WHERE segmento_cliente IS NULL OR regiao IS NULL",
    ),
    # gold.precos_competitividade
    (
        "gold.precos_competitividade: id_produto único",
        "SELECT count(*) - count(DISTINCT id_produto) FROM gold.precos_competitividade",
    ),
    # Todas as golds
    (
        # O Genie depende dos comentários; tabelas __materialization* são internas do pipeline.
        "gold: toda coluna com comentário",
        """SELECT count(*) FROM information_schema.columns
           WHERE table_schema = 'gold'
             AND NOT startswith(table_name, '__materialization')
             AND (comment IS NULL OR trim(comment) = '')""",
    ),
]

resultados = []
for nome, consulta in TESTES:
    linhas_com_problema = spark.sql(consulta).first()[0]
    resultados.append((nome, int(linhas_com_problema), "OK" if linhas_com_problema == 0 else "FALHOU"))

display(spark.createDataFrame(resultados, "teste string, linhas_com_problema long, status string"))

# COMMAND ----------

falhas = [nome for nome, linhas, status in resultados if status == "FALHOU"]
assert not falhas, f"{len(falhas)} teste(s) de qualidade falharam: {falhas}"
