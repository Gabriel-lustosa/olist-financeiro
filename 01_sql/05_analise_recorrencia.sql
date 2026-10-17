-- =====================================================================
-- Projeto: Análise Financeira E-commerce Olist
-- Arquivo: 05_analise_recorrencia.sql
-- Objetivo: Medir recorrência de clientes e o peso dos one-shot na receita.
--          É o GABARITO das medidas/colunas DAX do Power BI: cada número
--          aqui tem que bater, ao centavo, com o que o modelo mostra
--          (ver 04_powerbi/medidas_dax.md).
--
-- Regras de negócio (as mesmas do DAX):
--   - Pessoa = customer_unique_id (customer_id muda a cada pedido!)
--   - Só conta pedido com order_status = 'delivered'
--   - Pedido = DISTINCT order_id (o grão da FatoVendas é ITEM)
-- =====================================================================

USE olist_financeiro;
GO


-- ---------------------------------------------------------------------
-- 0) Âncoras de receita
-- Receita total     -> todos os status       (esperado: 15.843.553,24)
-- Receita realizada -> só 'delivered'        (esperado: 15.419.773,75)
-- ---------------------------------------------------------------------
SELECT
    SUM(valor_total)                                                  AS receita_total,
    SUM(CASE WHEN order_status = 'delivered' THEN valor_total END)    AS receita_realizada,
    COUNT(DISTINCT CASE WHEN order_status = 'delivered' THEN order_id END) AS pedidos_entregues  -- esperado: 96.478
FROM FatoVendas;


-- ---------------------------------------------------------------------
-- Base: uma linha por PESSOA, com qtd de pedidos entregues,
-- receita realizada e data da primeira compra entregue.
--
-- Por que LEFT JOIN: queremos TODAS as 96.096 pessoas da DimCliente,
-- inclusive quem nunca recebeu um pedido (qtd_pedidos = 0 / NULL).
-- Equivale à coluna DAX `Qtd Pedidos Entregues` (em branco = 0 aqui).
-- ---------------------------------------------------------------------
IF OBJECT_ID('tempdb..#pessoas') IS NOT NULL DROP TABLE #pessoas;

SELECT
    dc.customer_unique_id,
    COUNT(DISTINCT f.order_id)  AS qtd_pedidos,
    SUM(f.valor_total)          AS receita_realizada,
    MIN(dd.data_completa)       AS data_primeira_compra
INTO #pessoas
FROM DimCliente AS dc
LEFT JOIN FatoVendas AS f
       ON  f.sk_cliente   = dc.sk_cliente
       AND f.order_status = 'delivered'     -- filtro no ON (não no WHERE) pra não perder quem não tem entrega
LEFT JOIN DimData AS dd
       ON  dd.sk_data = f.sk_data
GROUP BY dc.customer_unique_id;
-- O aviso "valor nulo eliminado por uma agregação" é esperado: vem das
-- pessoas sem entrega (LEFT JOIN sem par). Pode ignorar.

SELECT COUNT(*) AS total_pessoas FROM #pessoas;   -- esperado: 96.096


-- ---------------------------------------------------------------------
-- 1) Distribuição: quantas pessoas fizeram 0, 1, 2, 3... pedidos
-- Gabarito da tabela "Qtd Pedidos Entregues x Contagem distinta" no PBI
--   0 -> 2.738 | 1 -> 90.557 | 2 -> 2.573 | 3 -> 181 | 4..15 -> 47
-- ---------------------------------------------------------------------
SELECT
    qtd_pedidos,
    COUNT(*) AS pessoas
FROM #pessoas
GROUP BY qtd_pedidos
ORDER BY qtd_pedidos;


-- ---------------------------------------------------------------------
-- 2) Taxa de retenção: recorrentes / quem recebeu pelo menos 1 pedido
--   clientes_unicos -> 93.358 | recorrentes -> 2.801 | taxa -> 3,0%
-- ---------------------------------------------------------------------
SELECT
    SUM(CASE WHEN qtd_pedidos >= 1 THEN 1 ELSE 0 END)  AS clientes_unicos,
    SUM(CASE WHEN qtd_pedidos >= 2 THEN 1 ELSE 0 END)  AS clientes_recorrentes,
    CAST(100.0 * SUM(CASE WHEN qtd_pedidos >= 2 THEN 1 ELSE 0 END)
               / SUM(CASE WHEN qtd_pedidos >= 1 THEN 1 ELSE 0 END)
         AS DECIMAL(5,2))                               AS taxa_retencao_pct
FROM #pessoas;


-- ---------------------------------------------------------------------
-- 3) A tese: quanto da receita vem de quem comprou uma vez só?
--   one-shot -> 14.555.586,29 | recorrentes -> 864.187,46 | 94,4%
-- ---------------------------------------------------------------------
SELECT
    CASE WHEN qtd_pedidos >= 2 THEN N'Recorrente' ELSE N'Único' END  AS tipo_cliente,
    COUNT(*)                                                     AS pessoas,
    SUM(receita_realizada)                                       AS receita,
    CAST(100.0 * SUM(receita_realizada)
               / SUM(SUM(receita_realizada)) OVER ()             -- total geral via window function
         AS DECIMAL(5,2))                                        AS pct_receita
FROM #pessoas
GROUP BY CASE WHEN qtd_pedidos >= 2 THEN N'Recorrente' ELSE N'Único' END;
-- Obs.: 'Único' tem 93.295 pessoas porque inclui as 2.738 sem entrega
-- (receita NULL, não somam nada) — igual à coluna DAX `Tipo Cliente`.


-- ---------------------------------------------------------------------
-- 4) Coorte de aquisição: novos clientes por mês da 1ª compra entregue
-- Gabarito de `AnoMes Aquisicao` no PBI: 23 meses (2016-09 a 2018-08),
-- pico em 2017-11 (Black Friday) com 7.060 pessoas; 2.738 sem data.
-- ---------------------------------------------------------------------
SELECT
    YEAR(data_primeira_compra) * 100 + MONTH(data_primeira_compra)  AS anomes_aquisicao,
    COUNT(*)                                                       AS novos_clientes
FROM #pessoas
GROUP BY YEAR(data_primeira_compra) * 100 + MONTH(data_primeira_compra)
ORDER BY anomes_aquisicao;


-- ---------------------------------------------------------------------
-- 5) Matriz de retenção por coorte
-- Para cada coorte (mês da 1ª compra entregue) e cada K = meses depois
-- da aquisição: quantas pessoas da coorte tiveram pedido entregue no mês
-- coorte + K. Gabarito de [Clientes Ativos Coorte] / [% Retenção Coorte].
--
-- Mês vira índice (ano * 12 + mês) para a distância ser uma subtração:
-- 201801 - 201711 = 90 (errado); 24.217 - 24.215 = 2 (certo).
--
-- Esperado: 219 células com alguém ativo; K máximo = 20; soma de K = 0
-- = 93.358. Exemplos: 2017-11 (7.060 pessoas) -> mês 1: 40 (0,57%);
-- 2017-10 -> mês 1: 31 (0,72%), a maior célula entre coortes >= 700
-- pessoas. Retenção ponderada no mês 1: 421 / 87.214 = 0,48%
-- (exclui 2018-08, que ainda não teve um mês 1 nos dados).
-- ---------------------------------------------------------------------
WITH compras AS (   -- uma linha por pessoa x mês com pedido entregue
    SELECT DISTINCT
        dc.customer_unique_id,
        YEAR(dd.data_completa) * 12 + MONTH(dd.data_completa)  AS mes_indice
    FROM FatoVendas AS f
    JOIN DimCliente AS dc ON dc.sk_cliente = f.sk_cliente
    JOIN DimData    AS dd ON dd.sk_data    = f.sk_data
    WHERE f.order_status = 'delivered'
),
aquisicao AS (      -- mês da 1ª compra de cada pessoa
    SELECT customer_unique_id, MIN(mes_indice) AS aquisicao_indice
    FROM compras
    GROUP BY customer_unique_id
)
SELECT
    (a.aquisicao_indice - 1) / 12 * 100 + (a.aquisicao_indice - 1) % 12 + 1  AS anomes_aquisicao,
    c.mes_indice - a.aquisicao_indice                                      AS mes_relativo,
    COUNT(DISTINCT c.customer_unique_id)                                   AS clientes_ativos
FROM compras   AS c
JOIN aquisicao AS a ON a.customer_unique_id = c.customer_unique_id
GROUP BY a.aquisicao_indice, c.mes_indice - a.aquisicao_indice
ORDER BY anomes_aquisicao, mes_relativo;
-- % retenção = clientes_ativos / clientes_ativos do mes_relativo 0 da mesma coorte.


DROP TABLE #pessoas;
