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


-- ---------------------------------------------------------------------
-- 6) Receita por categoria e peso dos one-shot em cada uma
-- Gabarito da tabela de categorias (DimProduto[Categoria] no PBI troca
-- "_" por " " e NULL por "sem categoria"). 74 categorias + sem categoria.
--   beleza_saude 1.412.089,53 (9,2%; 95,5% one-shot) | relogios_presentes
--   1.264.333,12 (8,2%; 95,5%) | cama_mesa_banho 1.225.209,26 (7,9%; 90,7%)
-- Todas as categorias com receita >= 100 mil têm 88,8% a 98,1% one-shot:
-- o problema de retenção é do negócio, não de uma categoria.
-- ---------------------------------------------------------------------
SELECT
    ISNULL(p.product_category_name, '(sem categoria)')               AS categoria,
    SUM(f.valor_total)                                               AS receita_realizada,
    CAST(100.0 * SUM(f.valor_total)
               / SUM(SUM(f.valor_total)) OVER ()  AS DECIMAL(5,2))   AS pct_da_receita,
    CAST(100.0 * SUM(CASE WHEN pe.qtd_pedidos < 2 THEN f.valor_total END)
               / SUM(f.valor_total)               AS DECIMAL(5,2))   AS pct_one_shot
FROM FatoVendas AS f
JOIN DimProduto AS p  ON p.sk_produto  = f.sk_produto
JOIN DimCliente AS dc ON dc.sk_cliente = f.sk_cliente
JOIN #pessoas   AS pe ON pe.customer_unique_id = dc.customer_unique_id   -- tipo de cliente é da PESSOA, não da categoria
WHERE f.order_status = 'delivered'
GROUP BY ISNULL(p.product_category_name, '(sem categoria)')
ORDER BY receita_realizada DESC;


-- ---------------------------------------------------------------------
-- 7) Retenção, ticket e frete por região
-- Mesma lógica do DAX: dentro de cada região, recorrente = pessoa com 2+
-- pedidos entregues NAQUELA região.
--   Sudeste  63.994 | 3,10% | R$ 150,48 | frete 13,2% | 64,6% da receita
--   Sul      13.383 | 2,90% | R$ 162,03 | frete 15,0% | 14,5%
--   Nordeste  8.813 | 2,29% | R$ 201,52 | frete 17,9% | 11,8%
--   C-Oeste   5.449 | 2,97% | R$ 177,09 | frete 15,0% |  6,5%
--   Norte     1.742 | 2,70% | R$ 223,46 | frete 18,5% |  2,6%
-- ---------------------------------------------------------------------
WITH regiao AS (
    SELECT sk_cliente, customer_unique_id,
        CASE
            WHEN customer_state IN ('SP','RJ','MG','ES')                          THEN 'Sudeste'
            WHEN customer_state IN ('PR','SC','RS')                               THEN 'Sul'
            WHEN customer_state IN ('DF','GO','MT','MS')                          THEN 'Centro-Oeste'
            WHEN customer_state IN ('AC','AP','AM','PA','RO','RR','TO')           THEN 'Norte'
            WHEN customer_state IN ('AL','BA','CE','MA','PB','PE','PI','RN','SE') THEN 'Nordeste'
            ELSE '?'
        END AS regiao
    FROM DimCliente
),
pessoa_regiao AS (
    SELECT
        r.regiao,
        r.customer_unique_id,
        COUNT(DISTINCT f.order_id)  AS pedidos,
        SUM(f.valor_total)          AS receita,
        SUM(f.freight_value)        AS frete
    FROM FatoVendas AS f
    JOIN regiao     AS r ON r.sk_cliente = f.sk_cliente
    WHERE f.order_status = 'delivered'
    GROUP BY r.regiao, r.customer_unique_id
)
SELECT
    regiao,
    COUNT(*)                                                       AS clientes_unicos,
    CAST(100.0 * SUM(CASE WHEN pedidos > 1 THEN 1 ELSE 0 END)
               / COUNT(*)                     AS DECIMAL(5,2))     AS taxa_retencao_pct,
    CAST(SUM(receita) / SUM(pedidos)          AS DECIMAL(10,2))    AS ticket_medio,
    CAST(100.0 * SUM(frete) / SUM(receita)    AS DECIMAL(5,2))     AS pct_frete,
    CAST(100.0 * SUM(receita)
               / SUM(SUM(receita)) OVER ()    AS DECIMAL(5,2))     AS pct_da_receita
FROM pessoa_regiao
GROUP BY regiao
ORDER BY clientes_unicos DESC;


DROP TABLE #pessoas;
