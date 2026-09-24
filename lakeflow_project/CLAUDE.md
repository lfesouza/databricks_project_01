# CLAUDE.md

Project guidance for AI agents lives in AGENTS.md.
Claude Code loads it via the import below.

@AGENTS.md

## Convenções do projeto (e-commerce)

- Perfil de CLI: sempre `DEFAULT` (`databricks ... -p DEFAULT`).
- Catálogo `ecommerce`, schemas `bronze`, `silver` e `gold`. Nunca use outro catálogo.
- A bronze é sobrescrita por outra ingestão; o pipeline só lê dela.
- Nomes de tabelas e colunas em português, snake_case, sem acento.
- Silver em Python (`from pyspark import pipelines as dp`), gold em SQL.
- Um arquivo por tabela: `src/lakeflow_project_etl/transformations/silver/<tabela>.py` e
  `src/lakeflow_project_etl/transformations/gold/<tabela>.sql`.
- Todas as tabelas são materialized views com leitura batch (`spark.read.table`), nunca streaming
  table, porque a bronze é sobrescrita a cada execução.
- Pipeline serverless, catálogo `ecommerce`, schema padrão `silver`. Golds publicadas como
  `gold.<tabela>`. Nomes no código sempre `schema.tabela`, sem catálogo.
- Cada arquivo começa com comentários explicando o PORQUÊ das regras, em português.
- Dinheiro sempre `DECIMAL(10,2)`.
- Problema de qualidade conhecido é MARCADO em uma coluna e medido com `@dp.expect` (warn).
  Nunca descarte linhas: apagar vendas mudaria a receita.
- `@dp.expect_all_or_fail` só para o que nunca pode acontecer.
- Sempre rode `databricks bundle validate --strict` antes do deploy.
- Testes de qualidade: `testes/testes_qualidade.py`, executado pelo Job "Pipeline E-commerce"
  depois do pipeline.

## Regras para toda gold (valem para todas as diretorias)

- SQL, um arquivo por tabela em `transformations/gold/`, com
  `CREATE OR REFRESH MATERIALIZED VIEW gold.<tabela>`.
- Declare TODAS as colunas entre parênteses com tipo e `COMMENT` (sem o tipo, o comentário é
  ignorado), e `COMMENT` na tabela dizendo quando usar a tabela.
- Comentários em português, com unidade (R$), regra de cálculo e avisos que evitem erro do Genie
  (ex.: o que não pode ser somado, o que é NULL e por quê).
- Inclua TODAS as vendas, inclusive de produto não cadastrado: dinheiro que entrou é receita.
- Período dos dados: 13/12/2025 a 11/01/2026 (cite nos comentários de colunas com valores do período).
- Toda gold nova ganha testes no notebook `testes/testes_qualidade.py`.

## Tabelas

| Tabela | Grão | Diretoria |
|---|---|---|
| silver.produtos | id_produto | — |
| silver.clientes | id_cliente | — |
| silver.preco_competidores | id_produto + nome_concorrente | — |
| silver.vendas | id_venda | — |
| gold.clientes_segmentacao | id_cliente (inclusive quem nunca comprou) | Customer Success |
| gold.vendas_temporais | data × hora × canal_venda | Comercial |
| gold.vendas_produtos | id_produto vendido | Comercial |
| gold.vendas_detalhadas | id_venda (CLUSTER BY data) | cruzamentos entre diretorias |
| gold.precos_competitividade | id_produto com preço de concorrente | Pricing |

Job "Pipeline E-commerce" (`resources/pipeline_ecommerce.job.yml`): roda o pipeline e depois
`testes/testes_qualidade.py`. Deploy: `databricks bundle validate --strict -t dev`,
`databricks bundle deploy -t dev`, `databricks bundle run pipeline_ecommerce -t dev`.

## Números de referência (bronze de 13/12/2025 a 11/01/2026)

Use para conferir qualquer mudança. Se um número mudar sem a bronze ter mudado, algo quebrou.

- **Bronze:** 3.020 vendas, 215 produtos, 50 clientes, 728 preços de concorrentes; sem nulos
  nem duplicatas.
- **Vendas:** 3.020 vendas, receita R$ 974.077,28 em silver.vendas e nas 3 golds de vendas;
  2.155 no ecommerce e 865 na loja_fisica.
- **Qualidade (expectations warn):**
  - 20 vendas de produto não cadastrado (R$ 4.240,01);
  - 5 vendas antes do cadastro do produto (R$ 325,88);
  - 55 preços de concorrente suspeitos.
- **Clientes:**
  - 11 com pronome de tratamento no nome.
  - Por região: Norte 17, Nordeste 12, Centro-Oeste 9, Sudeste 8, Sul 4.
- **gold.clientes_segmentacao:**
  - 50 clientes: 10 VIP, 25 TOP_TIER, 15 REGULAR.
  - Maior cliente: Ana Sophia Pereira (MG, R$ 30.716,63).
- **gold.vendas_produtos:** 205 produtos vendidos, dos quais 20 não cadastrados.
- **gold.precos_competitividade:**
  - 215 produtos, com 15 que têm preço suspeito e 30 que nunca venderam.
  - Classificação: MAIS_CARO_QUE_TODOS 35, MAIS_BARATO_QUE_TODOS 6, ACIMA_DA_MEDIA 92,
    ABAIXO_DA_MEDIA 76, NA_MEDIA 6.
