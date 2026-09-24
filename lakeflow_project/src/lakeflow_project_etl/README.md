# lakeflow_project_etl

Pipeline (Lakeflow Declarative Pipelines) da camada silver do e-commerce, no catálogo `ecommerce`.

- `transformations/silver/`: uma materialized view por arquivo, em Python, lendo de `bronze.*`.
- `transformations/gold/`: tabelas gold em SQL, uma por arquivo, publicadas como `gold.<tabela>`.

Convenções completas em `../../CLAUDE.md`.

Para atualizar uma tabela só: `databricks bundle run lakeflow_project_etl --refresh silver.vendas`.
