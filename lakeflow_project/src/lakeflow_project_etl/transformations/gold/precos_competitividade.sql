-- gold.precos_competitividade: nosso preço contra a concorrência (Diretoria de Pricing).
--
-- Por que estas regras:
-- - Uma linha por produto que tem preço de concorrente (Mercado Livre, Amazon, Magalu, Shopee):
--   JOIN de silver.produtos com a agregação de silver.preco_competidores. Sem preço de concorrente
--   não há comparação possível.
-- - Receita e itens vêm de silver.vendas com LEFT JOIN (0 se o produto nunca vendeu), para
--   priorizar onde agir: um produto caro que vende muito pesa mais que um que não vende.
-- - Diferenças em pontos percentuais com 2 casas: 10 = nosso preço 10% mais caro; negativo =
--   mais barato. Calculadas sobre o preço médio já arredondado, o mesmo exibido na tabela.
-- - Classificação avaliada NESTA ordem: MAIS_CARO_QUE_TODOS (acima do maior preço),
--   MAIS_BARATO_QUE_TODOS (abaixo do menor) e, no meio da faixa, ACIMA_DA_MEDIA,
--   ABAIXO_DA_MEDIA ou NA_MEDIA.
-- - Preço suspeito (concorrente abaixo de 60% do nosso preço) CONTINUA em todas as contas:
--   promoção relâmpago existe, e descartar o preço esconderia justamente o caso mais urgente.
--   possui_preco_suspeito só alerta que o preço precisa ser confirmado antes de reagir.
-- - Dinheiro e percentuais em DECIMAL(10,2).

CREATE OR REFRESH MATERIALIZED VIEW gold.precos_competitividade (
  id_produto STRING COMMENT 'Identificador único do produto. Chave da tabela (uma linha por produto com preço de concorrente).',
  nome_produto STRING COMMENT 'Nome do produto. ATENÇÃO: produtos diferentes têm o mesmo nome; para contar ou agrupar produtos use id_produto.',
  categoria STRING COMMENT 'Categoria do produto.',
  marca STRING COMMENT 'Marca do produto.',
  nosso_preco DECIMAL(10,2) COMMENT 'Nosso preço atual do produto, em R$ (preco_atual do cadastro).',
  preco_medio_concorrentes DECIMAL(10,2) COMMENT 'Média, em R$, dos preços coletados nos concorrentes (Mercado Livre, Amazon, Magalu, Shopee): ROUND(AVG, 2). Inclui preços suspeitos (ver possui_preco_suspeito).',
  preco_minimo_concorrentes DECIMAL(10,2) COMMENT 'Menor preço entre os concorrentes, em R$. Inclui preços suspeitos (ver possui_preco_suspeito).',
  preco_maximo_concorrentes DECIMAL(10,2) COMMENT 'Maior preço entre os concorrentes, em R$.',
  total_concorrentes BIGINT COMMENT 'Quantidade de concorrentes com preço coletado para o produto (de 1 a 4).',
  diferenca_pct_vs_media DECIMAL(10,2) COMMENT 'Diferença do nosso preço para a média dos concorrentes, em pontos percentuais: ROUND((nosso_preco - preco_medio_concorrentes) / preco_medio_concorrentes * 100, 2). 10 = 10% mais caro; negativo = mais barato. Não somar entre produtos.',
  diferenca_pct_vs_minimo DECIMAL(10,2) COMMENT 'Diferença do nosso preço para o menor preço dos concorrentes, em pontos percentuais: ROUND((nosso_preco - preco_minimo_concorrentes) / preco_minimo_concorrentes * 100, 2). 10 = 10% mais caro; negativo = mais barato. Não somar entre produtos.',
  classificacao_preco STRING COMMENT 'Posição do nosso preço, avaliada nesta ordem: MAIS_CARO_QUE_TODOS (acima do maior preço dos concorrentes), MAIS_BARATO_QUE_TODOS (abaixo do menor), ACIMA_DA_MEDIA, ABAIXO_DA_MEDIA ou NA_MEDIA (comparando com preco_medio_concorrentes). Valores sempre em maiúsculas.',
  possui_preco_suspeito BOOLEAN COMMENT 'true quando algum concorrente tem preço abaixo de 60% do nosso (possível erro de coleta ou promoção relâmpago). O preço continua em todas as contas; true só alerta que ele precisa ser confirmado antes de reagir.',
  receita DECIMAL(10,2) COMMENT 'Receita do produto em R$ no período de 13/12/2025 a 11/01/2026 (quantidade × preço unitário das vendas). 0 se o produto nunca vendeu. Use para priorizar onde agir.',
  itens_vendidos BIGINT COMMENT 'Unidades vendidas do produto no período de 13/12/2025 a 11/01/2026. 0 se o produto nunca vendeu.'
)
COMMENT 'Diretoria de Pricing: uma linha por produto com preço de concorrente (Mercado Livre, Amazon, Magalu, Shopee), comparando nosso preço com a média, o mínimo e o máximo da concorrência, com classificação, alerta de preço suspeito e receita do produto. Use para saber se estamos mais caros que a concorrência e em quais produtos agir (ex.: MAIS_CARO_QUE_TODOS com maior receita). Preços de concorrentes coletados em 11/01/2026; receita do período 13/12/2025 a 11/01/2026. Valores em R$.'
AS
WITH concorrentes AS (
  SELECT
    id_produto,
    CAST(ROUND(AVG(preco_concorrente), 2) AS DECIMAL(10,2)) AS preco_medio_concorrentes,
    MIN(preco_concorrente) AS preco_minimo_concorrentes,
    MAX(preco_concorrente) AS preco_maximo_concorrentes,
    COUNT(DISTINCT nome_concorrente) AS total_concorrentes,
    BOOL_OR(preco_suspeito) AS possui_preco_suspeito
  FROM silver.preco_competidores
  GROUP BY id_produto
),
vendas_por_produto AS (
  SELECT id_produto, SUM(receita) AS receita, SUM(quantidade) AS itens_vendidos
  FROM silver.vendas
  GROUP BY id_produto
)
SELECT
  p.id_produto,
  p.nome_produto,
  p.categoria,
  p.marca,
  p.preco_atual AS nosso_preco,
  c.preco_medio_concorrentes,
  c.preco_minimo_concorrentes,
  c.preco_maximo_concorrentes,
  c.total_concorrentes,
  CAST(ROUND((p.preco_atual - c.preco_medio_concorrentes) / c.preco_medio_concorrentes * 100, 2) AS DECIMAL(10,2))
    AS diferenca_pct_vs_media,
  CAST(ROUND((p.preco_atual - c.preco_minimo_concorrentes) / c.preco_minimo_concorrentes * 100, 2) AS DECIMAL(10,2))
    AS diferenca_pct_vs_minimo,
  CASE
    WHEN p.preco_atual > c.preco_maximo_concorrentes THEN 'MAIS_CARO_QUE_TODOS'
    WHEN p.preco_atual < c.preco_minimo_concorrentes THEN 'MAIS_BARATO_QUE_TODOS'
    WHEN p.preco_atual > c.preco_medio_concorrentes THEN 'ACIMA_DA_MEDIA'
    WHEN p.preco_atual < c.preco_medio_concorrentes THEN 'ABAIXO_DA_MEDIA'
    ELSE 'NA_MEDIA'
  END AS classificacao_preco,
  c.possui_preco_suspeito,
  CAST(COALESCE(v.receita, 0) AS DECIMAL(10,2)) AS receita,
  COALESCE(v.itens_vendidos, 0) AS itens_vendidos
FROM silver.produtos p
JOIN concorrentes c ON c.id_produto = p.id_produto
LEFT JOIN vendas_por_produto v ON v.id_produto = p.id_produto
