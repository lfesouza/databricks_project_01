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

## Convenções de dashboards (AI/BI)

- Um dashboard por diretoria, como código: `src/dashboards/<nome>.lvdash.json` com o recurso em
  `resources/<nome>.dashboard.yml` (`warehouse_id: ${var.warehouse_id}`, variável com lookup do
  warehouse "Serverless Starter Warehouse" no `databricks.yml`; `dataset_catalog: ${var.catalog}`;
  `dataset_schema: gold`).
- Consultas com o nome da tabela sem catálogo nem schema (`FROM vendas_temporais`), para o mesmo
  dashboard funcionar em dev e prod.
- Tudo em português: título, subtítulo com período e fonte dos dados, gráficos e eixos. Canais
  exibidos como "E-commerce" e "Loja física". Dinheiro em R$ (`currencyCode: BRL`).
- Layout de leitura rápida: título, filtros, uma linha de KPIs, gráficos e uma tabela de detalhe para agir.
- Período fixo 13/12/2025 a 11/01/2026: nunca `current_date()`.
- Regras que o gráfico não pode quebrar:
  - ticket médio = receita total ÷ número de vendas, nunca média de médias
    (`SUM(receita)/SUM(total_vendas)` em vendas_temporais, `COUNT(*)` em vendas_detalhadas,
    `SUM(total_compras)` em clientes_segmentacao);
  - nunca somar `clientes_unicos` entre linhas;
  - produto se conta e se agrupa por `id_produto` (há nomes repetidos);
  - dia da semana se compara pela receita MÉDIA por dia (`SUM(receita)/COUNT(DISTINCT data)`): o
    período tem 5 sábados e 5 domingos e só 4 de cada dia útil.
- Data e hora estão em UTC: diga isso no eixo/título.
- `diferenca_pct_*` está em pontos percentuais (10 = 10%): divida por 100 para usar o formato de %.
- Preço suspeito (`possui_preco_suspeito`) é erro de coleta ou promoção: sempre separe
  "Confirmado" de "Preço a conferir" em KPI, gráfico e tabela de Pricing.
- Top N agrega antes do LIMIT em dataset próprio, com parâmetros ligados aos mesmos filtros.
- Antes do deploy, teste TODAS as consultas dos datasets no warehouse e confira os KPIs com os
  números de referência abaixo.

| Dashboard | Arquivo | Tabelas |
|---|---|---|
| Diretoria Comercial | `diretoria_comercial` | gold.vendas_detalhadas |
| Diretoria de Customer Success | `diretoria_customer_success` | gold.clientes_segmentacao |
| Diretoria de Pricing | `diretoria_pricing` | gold.precos_competitividade |

- Botão "Ask Genie": `uiSettings.genieSpace.overrideId` de cada dashboard aponta para o space
  "Diretoria E-commerce" de DEV (`01f1b87dc664122ba8f03fc378899e4e`), fixo no JSON. Em prod o space
  tem outro id: troque o `overrideId` antes de publicar em prod.

## Convenções do Genie space (agente "Diretoria E-commerce")

- Um único space para as três diretorias. Conteúdo em `src/genie/diretoria_ecommerce.geniespace.json`
  (serialized space v2) e recurso em `resources/diretoria.genie_space.yml` (`warehouse_id:
  ${var.warehouse_id}`, `parent_path: ${workspace.root_path}` para não colidir com outro space de
  mesmo nome na pasta do usuário).
- Mudou uma instrução? Edite o JSON e faça deploy. Nunca ajuste o space pela interface: o próximo
  deploy sobrescreve.
- Os identificadores das tabelas e o SQL de exemplo estão escritos no JSON como
  `ecommerce.gold.<tabela>`, porque o arquivo não passa por variáveis do bundle. Se o catálogo mudar
  (ex.: em prod), troque no JSON.
- Só as 5 golds entram no space; nada de bronze ou silver.
- Instruções gerais curtas (até ~2.500 caracteres), só com regra de negócio que não cabe em
  comentário de coluna; não repita o comentário. Regra que falha em texto vai como SQL de exemplo
  ou como formato de resposta explícito.
- SQL de exemplo nunca repete as perguntas do teste de aceitação (senão o teste vira cola) e é
  testado no warehouse antes do deploy. IDs dos itens: 32 hex, ordenados.
- Teste de aceitação: 10 perguntas + 2 de limite ("Qual foi o nosso lucro?", "Quanto vendemos
  ontem?") pela API de conversa do Genie, comparando com SQL direto na gold. Acerto = resposta com
  todos os números esperados. Placar final: 10/10 e 2/2 (rodada 6).

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
