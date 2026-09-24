-- gold.vendas_detalhadas: uma linha por venda, com produto, cliente e segmento já cruzados.
--
-- Por que estas regras:
-- - Serve às perguntas que cruzam diretorias ("receita por região e categoria", "canal preferido
--   dos VIPs") e aos filtros cruzados do dashboard, sem que o Genie precise fazer joins.
-- - Parte de silver.vendas com LEFT JOIN, para não perder nenhuma venda: dinheiro que entrou é
--   receita. Produto não cadastrado recebe os mesmos rótulos de gold.vendas_produtos
--   ("Produto não cadastrado" / "Não cadastrado").
-- - segmento_cliente vem de gold.clientes_segmentacao, para que o segmento seja exatamente o
--   mesmo da Diretoria de Customer Success.
-- - Dinheiro em DECIMAL(10,2).
-- - CLUSTER BY (data): a maioria das consultas filtra por período, e o clustering por data reduz
--   os arquivos lidos.

CREATE OR REFRESH MATERIALIZED VIEW gold.vendas_detalhadas (
  id_venda STRING COMMENT 'Identificador único da venda. Chave da tabela (uma linha por venda).',
  data_venda TIMESTAMP COMMENT 'Data e hora da venda (UTC).',
  data DATE COMMENT 'Data da venda (UTC). Período dos dados: 13/12/2025 a 11/01/2026.',
  dia_semana STRING COMMENT 'Dia da semana da venda em português: Domingo, Segunda, Terça, Quarta, Quinta, Sexta ou Sábado. Para ordenar, use dia_semana_num.',
  dia_semana_num INT COMMENT 'Número do dia da semana: 1 = Domingo, 2 = Segunda, ..., 7 = Sábado.',
  hora INT COMMENT 'Hora do dia da venda (UTC), de 0 a 23.',
  canal_venda STRING COMMENT 'Canal da venda: ecommerce (loja online) ou loja_fisica. Valores sempre em minúsculas.',
  id_produto STRING COMMENT 'Identificador do produto vendido. Para contar produtos use COUNT(DISTINCT id_produto), nunca o nome.',
  nome_produto STRING COMMENT 'Nome do produto. ATENÇÃO: produtos diferentes têm o mesmo nome; conte por id_produto. "Produto não cadastrado" quando o produto não existe no cadastro.',
  categoria STRING COMMENT 'Categoria do produto. "Não cadastrado" quando o produto não existe no cadastro.',
  marca STRING COMMENT 'Marca do produto. "Não cadastrado" quando o produto não existe no cadastro.',
  faixa_preco STRING COMMENT 'Faixa pelo preço atual do produto: PREMIUM (acima de R$ 1.000), MEDIO (acima de R$ 500 até R$ 1.000) ou BASICO (até R$ 500). "Não cadastrado" quando o produto não existe no cadastro.',
  id_cliente STRING COMMENT 'Identificador do cliente que comprou. Para contar clientes use COUNT(DISTINCT id_cliente).',
  nome_cliente STRING COMMENT 'Nome do cliente em formato título, sem pronome de tratamento.',
  estado STRING COMMENT 'Sigla da UF do cliente em maiúsculas (ex.: SP, MG).',
  regiao STRING COMMENT 'Região do IBGE do cliente: Norte, Nordeste, Centro-Oeste, Sudeste ou Sul.',
  segmento_cliente STRING COMMENT 'Segmento do cliente (o mesmo de gold.clientes_segmentacao): VIP (receita no período >= R$ 22.000,00), TOP_TIER (R$ 17.000,00 a R$ 21.999,99) ou REGULAR (abaixo de R$ 17.000,00).',
  quantidade BIGINT COMMENT 'Unidades do produto nesta venda.',
  preco_unitario DECIMAL(10,2) COMMENT 'Preço unitário praticado na venda, em R$.',
  receita DECIMAL(10,2) COMMENT 'Receita da venda em R$: quantidade × preço unitário. Some com SUM(receita) para totais.',
  produto_cadastrado BOOLEAN COMMENT 'true quando o produto existe no cadastro; false para venda de produto não cadastrado (a receita é contada normalmente).',
  venda_antes_do_cadastro BOOLEAN COMMENT 'true quando a venda aconteceu antes da data de criação do produto no cadastro (problema de qualidade da origem; a venda é contada normalmente).'
)
COMMENT 'Uma linha por venda com produto, cliente, região e segmento já cruzados. Use para perguntas que cruzam diretorias (ex.: receita por região e categoria, canal preferido dos clientes VIP) e para filtros cruzados do dashboard. Para totais por dia/hora/canal prefira gold.vendas_temporais; por produto, gold.vendas_produtos; por cliente, gold.clientes_segmentacao. Período dos dados: 13/12/2025 a 11/01/2026. Valores em R$.'
CLUSTER BY (data)
AS
SELECT
  v.id_venda,
  v.data_venda,
  v.data,
  v.dia_semana,
  v.dia_semana_num,
  v.hora,
  v.canal_venda,
  v.id_produto,
  COALESCE(p.nome_produto, 'Produto não cadastrado') AS nome_produto,
  COALESCE(p.categoria, 'Não cadastrado') AS categoria,
  COALESCE(p.marca, 'Não cadastrado') AS marca,
  COALESCE(p.faixa_preco, 'Não cadastrado') AS faixa_preco,
  v.id_cliente,
  c.nome_cliente,
  c.estado,
  c.regiao,
  c.segmento_cliente,
  v.quantidade,
  v.preco_unitario,
  v.receita,
  v.produto_cadastrado,
  v.venda_antes_do_cadastro
FROM silver.vendas v
LEFT JOIN silver.produtos p ON p.id_produto = v.id_produto
LEFT JOIN gold.clientes_segmentacao c ON c.id_cliente = v.id_cliente
