-- gold.clientes_segmentacao: carteira de clientes da Diretoria de Customer Success.
--
-- Por que estas regras:
-- - Uma linha por cliente, INCLUSIVE quem nunca comprou (LEFT JOIN a partir de silver.clientes,
--   receita zero): esse é justamente o cliente que o time de CS precisa ativar.
-- - Entram TODAS as vendas, inclusive de produto não cadastrado: dinheiro que entrou é receita.
-- - Todas as colunas são declaradas com tipo e COMMENT (sem o tipo o comentário é ignorado),
--   porque a tabela é usada em dashboard e no Genie, que escreve SQL a partir dos comentários.
-- - Dinheiro em DECIMAL(10,2).
-- - Segmentação definida com a diretora a partir da distribuição real da receita por cliente
--   (mínimo R$ 9.665,29, mediana R$ 19.104,78, máximo R$ 30.716,63 no período):
--     VIP      receita >= R$ 22.000,00
--     TOP_TIER receita >= R$ 17.000,00 e < R$ 22.000,00
--     REGULAR  receita <  R$ 17.000,00
--   Os limites antigos (VIP a partir de R$ 10.000, TOP_TIER a partir de R$ 5.000) não serviam:
--   todo cliente comprou pelo menos R$ 9.665,29, então 49 dos 50 viravam VIP e nenhum REGULAR,
--   e a segmentação não separava ninguém.
-- - ranking_receita usa ROW_NUMBER (sem empates) com id_cliente como desempate, para o ranking
--   ser estável entre execuções.

CREATE OR REFRESH MATERIALIZED VIEW gold.clientes_segmentacao (
  id_cliente STRING COMMENT 'Identificador único do cliente. Chave da tabela (uma linha por cliente).',
  nome_cliente STRING COMMENT 'Nome do cliente em formato título, sem pronome de tratamento (Sr., Sra., Srta., Dr., Dra.).',
  estado STRING COMMENT 'Sigla da UF do cliente em maiúsculas (ex.: SP, MG). Para o nome por extenso use nome_estado.',
  nome_estado STRING COMMENT 'Nome por extenso do estado do cliente (ex.: São Paulo).',
  regiao STRING COMMENT 'Região do IBGE do estado do cliente: Norte, Nordeste, Centro-Oeste, Sudeste ou Sul.',
  total_compras BIGINT COMMENT 'Quantidade de vendas (pedidos) do cliente no período de 13/12/2025 a 11/01/2026. Zero para quem nunca comprou.',
  receita DECIMAL(10,2) COMMENT 'Receita total do cliente em R$ no período de 13/12/2025 a 11/01/2026: soma de quantidade × preço unitário de todas as vendas, inclusive de produtos não cadastrados. Zero para quem nunca comprou. Já está somada por cliente: para o total geral use SUM(receita), nunca some ticket_medio.',
  ticket_medio DECIMAL(10,2) COMMENT 'Valor médio em R$ por venda do cliente: ROUND(AVG(receita da venda), 2). NULL para quem nunca comprou. Não somar entre clientes; para o ticket médio geral calcule SUM(receita) / SUM(total_compras).',
  primeira_compra TIMESTAMP COMMENT 'Data e hora (UTC) da primeira venda do cliente no período. NULL para quem nunca comprou.',
  ultima_compra TIMESTAMP COMMENT 'Data e hora (UTC) da venda mais recente do cliente no período. NULL para quem nunca comprou.',
  segmento_cliente STRING COMMENT 'Segmento pela receita do cliente no período: VIP (receita >= R$ 22.000,00), TOP_TIER (R$ 17.000,00 a R$ 21.999,99) ou REGULAR (abaixo de R$ 17.000,00, inclui quem nunca comprou). Valores sempre em maiúsculas.',
  ranking_receita INT COMMENT 'Posição do cliente ordenado por receita decrescente (1 = maior receita). Sem empates: em receita igual, desempata por id_cliente.'
)
COMMENT 'Diretoria de Customer Success: uma linha por cliente (inclusive quem nunca comprou) com localização (estado e região), receita, ticket médio, datas de primeira e última compra, segmento (VIP, TOP_TIER, REGULAR) e ranking por receita. Use para saber quem são os melhores clientes, onde estão e como a carteira se divide em segmentos. Período dos dados: 13/12/2025 a 11/01/2026. Valores em R$.'
AS
WITH compras_por_cliente AS (
  SELECT
    id_cliente,
    COUNT(*) AS total_compras,
    SUM(receita) AS receita,
    ROUND(AVG(receita), 2) AS ticket_medio,
    MIN(data_venda) AS primeira_compra,
    MAX(data_venda) AS ultima_compra
  FROM silver.vendas
  GROUP BY id_cliente
),
clientes_com_receita AS (
  SELECT
    c.id_cliente,
    c.nome_cliente,
    c.estado,
    c.nome_estado,
    c.regiao,
    COALESCE(v.total_compras, 0) AS total_compras,
    CAST(COALESCE(v.receita, 0) AS DECIMAL(10,2)) AS receita,
    CAST(v.ticket_medio AS DECIMAL(10,2)) AS ticket_medio,
    v.primeira_compra,
    v.ultima_compra
  FROM silver.clientes c
  LEFT JOIN compras_por_cliente v ON v.id_cliente = c.id_cliente
)
SELECT
  id_cliente,
  nome_cliente,
  estado,
  nome_estado,
  regiao,
  total_compras,
  receita,
  ticket_medio,
  primeira_compra,
  ultima_compra,
  CASE
    WHEN receita >= 22000 THEN 'VIP'
    WHEN receita >= 17000 THEN 'TOP_TIER'
    ELSE 'REGULAR'
  END AS segmento_cliente,
  ROW_NUMBER() OVER (ORDER BY receita DESC, id_cliente) AS ranking_receita
FROM clientes_com_receita
