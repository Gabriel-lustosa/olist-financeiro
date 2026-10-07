-- =====================================================================
-- Projeto: Análise Financeira E-commerce Olist
-- Arquivo: 02_load_data.sql
-- Objetivo: Carregar os 6 CSVs Olist nas tabelas OPERACIONAIS criadas
--           no script 01, via BULK INSERT.
--
-- Padrão de BULK INSERT (usado em todos):
--   FORMAT          = 'CSV'      -> respeita aspas em campos com vírgula
--   FIRSTROW        = 2          -> pula o cabeçalho
--   FIELDTERMINATOR = ','        -> separador de coluna
--   ROWTERMINATOR   = '0x0a'     -> LF (CSVs vindos do Kaggle são Unix)
--   CODEPAGE        = '65001'    -> UTF-8 (acentos em city, review, ...)
--   TABLOCK                      -> lock exclusivo p/ acelerar a carga
--
-- Pré-requisitos:
--   1) rodar 01_create_tables.sql antes (as tabelas precisam existir)
--   2) os 9 CSVs devem estar em: dados\*.csv
-- =====================================================================

USE olist_financeiro;
GO


-- ---------------------------------------------------------------------
-- Carga: customers
-- ---------------------------------------------------------------------
BULK INSERT customers
FROM 'C:\Users\Lustosa\OneDrive\Desktop\PORTFÓLIO\projeto_olist_financeiro\dados\olist_customers_dataset.csv'
WITH (
    FORMAT = 'CSV',
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '0x0a',
    CODEPAGE = '65001',
    TABLOCK
);


-- ---------------------------------------------------------------------
-- Carga: orders
-- ---------------------------------------------------------------------
BULK INSERT orders
FROM 'C:\Users\Lustosa\OneDrive\Desktop\PORTFÓLIO\projeto_olist_financeiro\dados\olist_orders_dataset.csv'
WITH (
    FORMAT = 'CSV',
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '0x0a',
    CODEPAGE = '65001',
    TABLOCK
);


-- ---------------------------------------------------------------------
-- Carga: order_items
-- ---------------------------------------------------------------------
BULK INSERT order_items
FROM 'C:\Users\Lustosa\OneDrive\Desktop\PORTFÓLIO\projeto_olist_financeiro\dados\olist_order_items_dataset.csv'
WITH (
    FORMAT = 'CSV',
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '0x0a',
    CODEPAGE = '65001',
    TABLOCK
);


-- ---------------------------------------------------------------------
-- Carga: order_payments
-- ---------------------------------------------------------------------
BULK INSERT order_payments
FROM 'C:\Users\Lustosa\OneDrive\Desktop\PORTFÓLIO\projeto_olist_financeiro\dados\olist_order_payments_dataset.csv'
WITH (
    FORMAT = 'CSV',
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '0x0a',
    CODEPAGE = '65001',
    TABLOCK
);


-- ---------------------------------------------------------------------
-- Carga: order_reviews
--
-- Atenção: review_comment_message é texto livre em PT-BR e pode conter
-- vírgulas e quebras de linha DENTRO das aspas. FORMAT='CSV' já cuida
-- disso (respeita RFC 4180). Se aparecer erro de "unexpected end of
-- file" aqui, provavelmente é um registro com aspas mal fechadas na
-- origem — nesse caso, quarentenar o registro e seguir.
-- ---------------------------------------------------------------------
BULK INSERT order_reviews
FROM 'C:\Users\Lustosa\OneDrive\Desktop\PORTFÓLIO\projeto_olist_financeiro\dados\olist_order_reviews_dataset.csv'
WITH (
    FORMAT = 'CSV',
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '0x0a',
    CODEPAGE = '65001',
    TABLOCK
);


-- ---------------------------------------------------------------------
-- Carga: geolocation
--
-- Maior arquivo (~1M linhas) — a carga leva mais tempo. TABLOCK ajuda.
-- ---------------------------------------------------------------------
BULK INSERT geolocation
FROM 'C:\Users\Lustosa\OneDrive\Desktop\PORTFÓLIO\projeto_olist_financeiro\dados\olist_geolocation_dataset.csv'
WITH (
    FORMAT = 'CSV',
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '0x0a',
    CODEPAGE = '65001',
    TABLOCK
);


-- ---------------------------------------------------------------------
-- Validação: contagem de linhas por tabela
-- Comparar com os totais esperados (do README do dataset Olist):
--   customers      ~99.441
--   orders         ~99.441
--   order_items    ~112.650
--   order_payments ~103.886
--   order_reviews  ~99.224
--   geolocation    ~1.000.163
-- ---------------------------------------------------------------------
SELECT 'customers'      AS tabela, COUNT(*) AS total FROM customers
UNION ALL
SELECT 'orders',         COUNT(*) FROM orders
UNION ALL
SELECT 'order_items',    COUNT(*) FROM order_items
UNION ALL
SELECT 'order_payments', COUNT(*) FROM order_payments
UNION ALL
SELECT 'order_reviews',  COUNT(*) FROM order_reviews
UNION ALL
SELECT 'geolocation',    COUNT(*) FROM geolocation
ORDER BY tabela;


-- ---------------------------------------------------------------------
-- Smoke test relacional: join orders x order_payments
-- (era o conteúdo antigo deste arquivo — mantido como sanity check)
-- ---------------------------------------------------------------------
SELECT TOP 10
    o.order_id,
    o.order_status,
    o.order_purchase_timestamp,
    p.payment_type,
    p.payment_value
FROM orders          AS o
INNER JOIN order_payments AS p
    ON o.order_id = p.order_id;
