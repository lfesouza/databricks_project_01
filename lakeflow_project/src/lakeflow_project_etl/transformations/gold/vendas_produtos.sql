-- gold.vendas_produtos: desempenho de vendas por produto (Diretoria Comercial).
--
-- Por que estas regras:
-- - Uma linha por produto VENDIDO: parte de silver.vendas com LEFT JOIN em silver.produtos, para
--   que vendas de produto não cadastrado continuem na conta (dinheiro que entrou é receita).
--   Produtos cadastrados que nunca venderam não aparecem aqui.
-- - Produto não cadastrado recebe nome "Produto não cadastrado" e categoria, marca e faixa_preco
--   "Não cadastrado", em vez de NULL, para aparecerem com um rótulo claro no dashboard e no Genie.
-- - Produtos diferentes podem ter o mesmo nome; a chave é id_produto e o comentário avisa o Genie
--   para contar por id_produto, nunca por nome.
-- - Receita e ticket médio em DECIMAL(10,2).
-- - Rankings com ROW_NUMBER (sem empates), desempatando por id_produto para ficarem estáveis.

CREATE OR REFRESH MATERIALIZED VIEW gold.vendas_produtos (
  id_produto STRING COMMENT 'Identificador único do produto. Chave da tabela (uma linha por produto vendido).',
  nome_produto STRING COMMENT 'Nome do produto. ATENÇÃO: produtos diferentes têm o mesmo nome; para contar ou agrupar produtos use id_produto, nunca nome_produto. "Produto não cadastrado" quando o produto vendido não existe no cadastro.',
  categoria STRING COMMENT 'Categoria do produto. "Não cadastrado" quando o produto vendido não existe no cadastro.',
  marca STRING COMMENT 'Marca do produto. "Não cadastrado" quando o produto vendido não existe no cadastro.',
  faixa_preco STRING COMMENT 'Faixa pelo preço atual do produto: PREMIUM (acima de R$ 1.000), MEDIO (acima de R$ 500 até R$ 1.000) ou BASICO (até R$ 500). "Não cadastrado" quando o produto não existe no cadastro.',
  produto_cadastrado BOOLEAN COMMENT 'true quando o produto existe no cadastro de produtos; false para vendas de produto não cadastrado (a receita delas é contada normalmente).',
  total_vendas BIGINT COMMENT 'Quantidade de vendas (pedidos) do produto no período de 13/12/2025 a 11/01/2026.',
  itens_vendidos BIGINT COMMENT 'Soma das unidades vendidas do produto no período de 13/12/2025 a 11/01/2026.',
  receita DECIMAL(10,2) COMMENT 'Receita do produto em R$ no período de 13/12/2025 a 11/01/2026: soma de quantidade × preço unitário. Pode ser somada entre produtos.',
  ticket_medio DECIMAL(10,2) COMMENT 'Valor médio em R$ por venda do produto: ROUND(AVG(receita da venda), 2). Não somar nem fazer média simples entre produtos; para o ticket geral use SUM(receita) / SUM(total_vendas).',
  ranking_receita INT COMMENT 'Posição do produto entre todos os produtos, por receita decrescente (1 = maior receita). Sem empates: desempata por id_produto.',
  ranking_na_categoria INT COMMENT 'Posição do produto dentro da sua categoria, por receita decrescente (1 = maior receita da categoria). Sem empates: desempata por id_produto.'
)
COMMENT 'Diretoria Comercial: uma linha por produto vendido, com nome, categoria, marca, faixa de preço, total de vendas, itens, receita em R$, ticket médio e rankings geral e por categoria. Use para perguntas sobre COM QUAIS PRODUTOS vendemos: produtos e categorias mais vendidos. Inclui vendas de produtos não cadastrados (rótulo "Não cadastrado"). Período dos dados: 13/12/2025 a 11/01/2026.'
AS
WITH vendas_por_produto AS (
  SELECT
    v.id_produto,
    COALESCE(p.nome_produto, 'Produto não cadastrado') AS nome_produto,
    COALESCE(p.categoria, 'Não cadastrado') AS categoria,
    COALESCE(p.marca, 'Não cadastrado') AS marca,
    COALESCE(p.faixa_preco, 'Não cadastrado') AS faixa_preco,
    p.id_produto IS NOT NULL AS produto_cadastrado,
    COUNT(*) AS total_vendas,
    SUM(v.quantidade) AS itens_vendidos,
    CAST(SUM(v.receita) AS DECIMAL(10,2)) AS receita,
    CAST(ROUND(AVG(v.receita), 2) AS DECIMAL(10,2)) AS ticket_medio
  FROM silver.vendas v
  LEFT JOIN silver.produtos p ON p.id_produto = v.id_produto
  GROUP BY ALL
)
SELECT
  *,
  ROW_NUMBER() OVER (ORDER BY receita DESC, id_produto) AS ranking_receita,
  ROW_NUMBER() OVER (PARTITION BY categoria ORDER BY receita DESC, id_produto) AS ranking_na_categoria
FROM vendas_por_produto
