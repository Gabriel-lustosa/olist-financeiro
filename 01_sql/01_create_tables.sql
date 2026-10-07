-- =====================================================================
-- Projeto: Análise Financeira E-commerce Olist
-- Arquivo: 01_create_tables.sql
-- Objetivo: Criar o banco `olist_financeiro` e as 6 tabelas OPERACIONAIS
--           (staging) que espelham 1:1 os CSVs do Kaggle. Essas tabelas
--           são a MATÉRIA-PRIMA — as dimensões e a fato (script 04) são
--           construídas a partir delas.
--
-- Convenções:
--   * Nomes das tabelas e colunas em snake_case, iguais aos CSVs (sem
--     renomear), pra rastreabilidade direta com a origem.
--   * SEM FKs entre tabelas operacionais: BULK INSERT rodaria muito mais
--     lento com constraints checadas linha a linha, e a integridade
--     referencial "de verdade" fica na FatoVendas (script 04).
--   * Datas como DATETIME2 (precisão maior que DATETIME e alinhado
--     com o padrão atual do SQL Server).
--   * Textos livres (review comment) como NVARCHAR(MAX) — podem conter
--     acentos e serem longos.
-- =====================================================================


-- ---------------------------------------------------------------------
-- Cria o banco se não existir e conecta nele
-- ---------------------------------------------------------------------
IF DB_ID('olist_financeiro') IS NULL
    CREATE DATABASE olist_financeiro;
GO

USE olist_financeiro;
GO


-- ---------------------------------------------------------------------
-- TABELA: customers
-- Origem: olist_customers_dataset.csv (99.441 linhas)
--
-- ATENÇÃO Olist:
--   customer_id       -> chave de SESSÃO de compra (muda a cada pedido)
--   customer_unique_id -> identifica a PESSOA real (recorrência)
-- A tabela `orders` referencia customer_id, por isso ele é a PK aqui.
-- ---------------------------------------------------------------------
CREATE TABLE customers (
    customer_id              VARCHAR(50) NOT NULL,
    customer_unique_id       VARCHAR(50),
    customer_zip_code_prefix VARCHAR(10),
    customer_city            VARCHAR(100),
    customer_state           CHAR(2),

    CONSTRAINT PK_customers PRIMARY KEY (customer_id)
);


-- ---------------------------------------------------------------------
-- TABELA: orders
-- Origem: olist_orders_dataset.csv (~99.441 linhas)
--
-- Datas NULLable de propósito: pedidos cancelados/pendentes não têm
-- approved_at, delivered_*, etc.
-- ---------------------------------------------------------------------
CREATE TABLE orders (
    order_id                      VARCHAR(50) NOT NULL,
    customer_id                   VARCHAR(50) NOT NULL,
    order_status                  VARCHAR(20),   -- delivered, shipped, canceled, ...
    order_purchase_timestamp      DATETIME2,     -- evento de RECEITA (usado no fato)
    order_approved_at             DATETIME2,
    order_delivered_carrier_date  DATETIME2,
    order_delivered_customer_date DATETIME2,
    order_estimated_delivery_date DATETIME2,

    CONSTRAINT PK_orders PRIMARY KEY (order_id)
);


-- ---------------------------------------------------------------------
-- TABELA: order_items
-- Origem: olist_order_items_dataset.csv (112.650 linhas)
--
-- PK COMPOSTA (order_id, order_item_id): um pedido pode ter N itens
-- e cada item é numerado sequencialmente dentro do pedido.
-- Esse é o GRÃO da FatoVendas.
-- ---------------------------------------------------------------------
CREATE TABLE order_items (
    order_id            VARCHAR(50)   NOT NULL,
    order_item_id       INT           NOT NULL,   -- 1, 2, 3... dentro do pedido
    product_id          VARCHAR(50)   NOT NULL,
    seller_id           VARCHAR(50)   NOT NULL,
    shipping_limit_date DATETIME2,
    price               DECIMAL(10,2) NOT NULL,
    freight_value       DECIMAL(10,2) NOT NULL,

    CONSTRAINT PK_order_items PRIMARY KEY (order_id, order_item_id)
);


-- ---------------------------------------------------------------------
-- TABELA: order_payments
-- Origem: olist_order_payments_dataset.csv (~103.886 linhas)
--
-- PK COMPOSTA (order_id, payment_sequential): um pedido pode ser pago
-- com MAIS DE UMA forma (ex.: parte no cartão + parte no voucher),
-- e payment_sequential enumera cada pagamento dentro do pedido.
-- ---------------------------------------------------------------------
CREATE TABLE order_payments (
    order_id             VARCHAR(50)   NOT NULL,
    payment_sequential   INT           NOT NULL,   -- 1, 2, 3... dentro do pedido
    payment_type         VARCHAR(20),              -- credit_card, boleto, voucher, debit_card
    payment_installments INT,                      -- nº de parcelas (0 quando à vista/boleto)
    payment_value        DECIMAL(10,2) NOT NULL,

    CONSTRAINT PK_order_payments PRIMARY KEY (order_id, payment_sequential)
);


-- ---------------------------------------------------------------------
-- TABELA: order_reviews
-- Origem: olist_order_reviews_dataset.csv (~99.224 linhas)
--
-- review_id é a PK; um pedido pode até ter mais de uma review na
-- prática (edge case do dataset), então NÃO usamos order_id como PK.
--
-- Comment title/message em NVARCHAR(MAX) — texto livre em português,
-- com acentos e possivelmente longo.
-- ---------------------------------------------------------------------
CREATE TABLE order_reviews (
    review_id               VARCHAR(50) NOT NULL,
    order_id                VARCHAR(50) NOT NULL,
    review_score            INT,                  -- 1..5
    review_comment_title    NVARCHAR(MAX),
    review_comment_message  NVARCHAR(MAX),
    review_creation_date    DATETIME2,
    review_answer_timestamp DATETIME2,

    CONSTRAINT PK_order_reviews PRIMARY KEY (review_id)
);


-- ---------------------------------------------------------------------
-- TABELA: geolocation
-- Origem: olist_geolocation_dataset.csv (~1.000.163 linhas)
--
-- SEM PK: o mesmo CEP aparece várias vezes (uma linha por
-- lat/lng diferente registrada). Usada só p/ enriquecer análises
-- geográficas — ex.: agregar por cidade/estado.
-- ---------------------------------------------------------------------
CREATE TABLE geolocation (
    geolocation_zip_code_prefix VARCHAR(10),
    geolocation_lat             DECIMAL(15,10),
    geolocation_lng             DECIMAL(15,10),
    geolocation_city            VARCHAR(100),
    geolocation_state           CHAR(2)
);


-- ---------------------------------------------------------------------
-- Validação: as 6 tabelas foram criadas?
-- ---------------------------------------------------------------------
SELECT name AS tabela
FROM sys.tables
WHERE name IN ('customers', 'orders', 'order_items',
               'order_payments', 'order_reviews', 'geolocation')
ORDER BY name;
-- esperado: 6 linhas
