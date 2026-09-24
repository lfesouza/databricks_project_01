-- gold.vendas_temporais: quanto vendemos, quando e em qual canal (Diretoria Comercial).
--
-- Por que estas regras:
-- - Grão data × hora × canal_venda: responde "quando vendemos" (dia, hora, dia da semana) e
--   "em qual canal" sem obrigar o dashboard a agregar 3.020 vendas a cada consulta.
-- - Entram TODAS as vendas, inclusive de produto não cadastrado: dinheiro que entrou é receita.
-- - Receita em DECIMAL(10,2).
-- - clientes_unicos é COUNT DISTINCT dentro da linha e NÃO pode ser somado entre linhas: o mesmo
--   cliente compra em horas e dias diferentes e seria contado várias vezes. O comentário da
--   coluna avisa o Genie e aponta gold.clientes_segmentacao para clientes únicos no período.
-- - Horas e datas em UTC, como na silver.

CREATE OR REFRESH MATERIALIZED VIEW gold.vendas_temporais (
  data DATE COMMENT 'Data da venda (UTC). Período dos dados: 13/12/2025 a 11/01/2026.',
  dia_semana STRING COMMENT 'Dia da semana da venda em português: Domingo, Segunda, Terça, Quarta, Quinta, Sexta ou Sábado. Para ordenar, use dia_semana_num.',
  dia_semana_num INT COMMENT 'Número do dia da semana: 1 = Domingo, 2 = Segunda, ..., 7 = Sábado. Use para ordenar os dias.',
  hora INT COMMENT 'Hora do dia da venda (UTC), de 0 a 23.',
  canal_venda STRING COMMENT 'Canal da venda: ecommerce (loja online) ou loja_fisica. Valores sempre em minúsculas.',
  total_vendas BIGINT COMMENT 'Quantidade de vendas (pedidos) na data, hora e canal. Pode ser somada entre linhas.',
  itens_vendidos BIGINT COMMENT 'Soma das quantidades (unidades de produto) vendidas na data, hora e canal. Pode ser somada entre linhas.',
  receita DECIMAL(10,2) COMMENT 'Receita em R$ na data, hora e canal: soma de quantidade × preço unitário, inclusive vendas de produtos não cadastrados. Pode ser somada entre linhas.',
  clientes_unicos BIGINT COMMENT 'Clientes distintos que compraram nesta data, hora e canal. ATENÇÃO: NÃO somar entre linhas (o mesmo cliente aparece em várias horas e dias). Para clientes únicos no período, use COUNT(*) em gold.clientes_segmentacao com total_compras > 0.'
)
COMMENT 'Diretoria Comercial: vendas agregadas por data × hora × canal_venda (ecommerce ou loja_fisica), com total de vendas, itens, receita em R$ e clientes únicos. Use para perguntas de QUANDO e ONDE (canal) vendemos: evolução diária, horários de pico, dias da semana. Período dos dados: 13/12/2025 a 11/01/2026, horários em UTC.'
AS
SELECT
  data,
  dia_semana,
  dia_semana_num,
  hora,
  canal_venda,
  COUNT(*) AS total_vendas,
  SUM(quantidade) AS itens_vendidos,
  CAST(SUM(receita) AS DECIMAL(10,2)) AS receita,
  COUNT(DISTINCT id_cliente) AS clientes_unicos
FROM silver.vendas
GROUP BY data, dia_semana, dia_semana_num, hora, canal_venda
