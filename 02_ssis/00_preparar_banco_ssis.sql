-- =====================================================================
-- Projeto: Análise Financeira E-commerce Olist
-- Arquivo: 02_ssis/00_preparar_banco_ssis.sql
-- Objetivo: Criar o banco `olist_financeiro_ssis` com a MESMA estrutura
--          do DW feito em SQL (staging + dimensões + fato), porém VAZIO.
--          Quem enche essas tabelas é o pacote SSIS (projeto olist_etl).
--
-- Por que um banco separado?
--   * O DW oficial (`olist_financeiro`) alimenta o Power BI — não dá pra
--     arriscar deixar ele quebrado no meio de uma carga em teste.
--   * Com os dois bancos lado a lado, dá pra PROVAR que o SSIS reproduz
--     o pipeline SQL: mesmas contagens, mesma receita (validação no fim
--     da trilha SSIS).
--
-- Escopo: só as 6 tabelas de origem que alimentam o star schema.
--   payments, reviews e geolocation não são usadas em nenhuma análise.
--
-- Pode rodar de novo quando quiser: ele DERRUBA e recria o banco.
-- =====================================================================

USE master;
GO

-- Derruba o banco de teste se já existir (SINGLE_USER fecha conexões
-- abertas, ex.: o Visual Studio ainda conectado depois de um debug)
IF DB_ID('olist_financeiro_ssis') IS NOT NULL
BEGIN
    ALTER DATABASE olist_financeiro_ssis SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE olist_financeiro_ssis;
END
GO

CREATE DATABASE olist_financeiro_ssis;
GO

USE olist_financeiro_ssis;
GO


-- =====================================================================
-- STAGING: tabelas operacionais (cópia fiel dos CSVs)
-- Mesma DDL dos scripts 01_sql/01 e 01_sql/03
-- =====================================================================
CREATE TABLE customers (
    customer_id              VARCHAR(50) NOT NULL,
    customer_unique_id       VARCHAR(50),
    customer_zip_code_prefix VARCHAR(10),
    customer_city            VARCHAR(100),
    customer_state           CHAR(2),

    CONSTRAINT PK_customers PRIMARY KEY (customer_id)
);

CREATE TABLE orders (
    order_id                      VARCHAR(50) NOT NULL,
    customer_id                   VARCHAR(50) NOT NULL,
    order_status                  VARCHAR(20),
    order_purchase_timestamp      DATETIME2,
    order_approved_at             DATETIME2,
    order_delivered_carrier_date  DATETIME2,
    order_delivered_customer_date DATETIME2,
    order_estimated_delivery_date DATETIME2,

    CONSTRAINT PK_orders PRIMARY KEY (order_id)
);

CREATE TABLE order_items (
    order_id            VARCHAR(50)   NOT NULL,
    order_item_id       INT           NOT NULL,
    product_id          VARCHAR(50)   NOT NULL,
    seller_id           VARCHAR(50)   NOT NULL,
    shipping_limit_date DATETIME2,
    price               DECIMAL(10,2) NOT NULL,
    freight_value       DECIMAL(10,2) NOT NULL,

    CONSTRAINT PK_order_items PRIMARY KEY (order_id, order_item_id)
);

CREATE TABLE products (
    product_id                 VARCHAR(50) NOT NULL,
    product_category_name      VARCHAR(100),
    product_name_length        INT,
    product_description_length INT,
    product_photos_qty         INT,
    product_weight_g           INT,
    product_length_cm          INT,
    product_height_cm          INT,
    product_width_cm           INT,

    CONSTRAINT PK_products PRIMARY KEY (product_id)
);

CREATE TABLE product_category_translation (
    product_category_name         VARCHAR(100) NOT NULL,
    product_category_name_english VARCHAR(100),

    CONSTRAINT PK_category_translation PRIMARY KEY (product_category_name)
);

CREATE TABLE sellers (
    seller_id              VARCHAR(50) NOT NULL,
    seller_zip_code_prefix VARCHAR(10),
    seller_city            VARCHAR(100),
    seller_state           CHAR(2),

    CONSTRAINT PK_sellers PRIMARY KEY (seller_id)
);


-- =====================================================================
-- DIMENSÕES (mesma DDL do 01_sql/04)
-- =====================================================================
CREATE TABLE DimVendedor (
    sk_vendedor            INT IDENTITY(1,1) NOT NULL,
    seller_id              VARCHAR(50)       NOT NULL,
    seller_zip_code_prefix VARCHAR(10),
    seller_city            VARCHAR(100),
    seller_state           CHAR(2),

    CONSTRAINT PK_DimVendedor PRIMARY KEY (sk_vendedor),
    CONSTRAINT UQ_DimVendedor_seller_id UNIQUE (seller_id)
);

CREATE TABLE DimProduto (
    sk_produto                    INT IDENTITY(1,1) NOT NULL,
    product_id                    VARCHAR(50)       NOT NULL,
    product_category_name         VARCHAR(100),
    product_category_name_english VARCHAR(100),
    product_weight_g              INT,
    product_length_cm             INT,
    product_height_cm             INT,
    product_width_cm              INT,

    CONSTRAINT PK_DimProduto PRIMARY KEY (sk_produto),
    CONSTRAINT UQ_DimProduto_product_id UNIQUE (product_id)
);

CREATE TABLE DimCliente (
    sk_cliente               INT IDENTITY(1,1) NOT NULL,
    customer_id              VARCHAR(50)       NOT NULL,
    customer_unique_id       VARCHAR(50),
    customer_zip_code_prefix VARCHAR(10),
    customer_city            VARCHAR(100),
    customer_state           CHAR(2),

    CONSTRAINT PK_DimCliente PRIMARY KEY (sk_cliente),
    CONSTRAINT UQ_DimCliente_customer_id UNIQUE (customer_id)
);

CREATE TABLE DimData (
    sk_data          INT          NOT NULL,   -- YYYYMMDD
    data_completa    DATE         NOT NULL,
    ano              INT          NOT NULL,
    trimestre        INT          NOT NULL,
    mes_numero       INT          NOT NULL,
    mes_nome         VARCHAR(20)  NOT NULL,
    dia              INT          NOT NULL,
    dia_semana_num   INT          NOT NULL,
    dia_semana_nome  VARCHAR(20)  NOT NULL,
    eh_fim_semana    BIT          NOT NULL,

    CONSTRAINT PK_DimData PRIMARY KEY (sk_data)
);


-- =====================================================================
-- FATO (mesma DDL do 01_sql/04)
-- =====================================================================
CREATE TABLE FatoVendas (
    sk_data        INT          NOT NULL,
    sk_cliente     INT          NOT NULL,
    sk_produto     INT          NOT NULL,
    sk_vendedor    INT          NOT NULL,

    order_id       VARCHAR(50)  NOT NULL,
    order_item_id  INT          NOT NULL,
    order_status   VARCHAR(20),

    price          DECIMAL(10,2) NOT NULL,
    freight_value  DECIMAL(10,2) NOT NULL,
    valor_total    AS (price + freight_value) PERSISTED,

    CONSTRAINT PK_FatoVendas PRIMARY KEY (order_id, order_item_id),

    CONSTRAINT FK_FatoVendas_Data     FOREIGN KEY (sk_data)     REFERENCES DimData(sk_data),
    CONSTRAINT FK_FatoVendas_Cliente  FOREIGN KEY (sk_cliente)  REFERENCES DimCliente(sk_cliente),
    CONSTRAINT FK_FatoVendas_Produto  FOREIGN KEY (sk_produto)  REFERENCES DimProduto(sk_produto),
    CONSTRAINT FK_FatoVendas_Vendedor FOREIGN KEY (sk_vendedor) REFERENCES DimVendedor(sk_vendedor)
);


-- ---------------------------------------------------------------------
-- Validação: 11 tabelas criadas, todas com 0 linhas
-- ---------------------------------------------------------------------
SELECT
    t.name       AS tabela,
    SUM(p.rows)  AS linhas
FROM sys.tables AS t
JOIN sys.partitions AS p
  ON p.object_id = t.object_id
 AND p.index_id IN (0, 1)
GROUP BY t.name
ORDER BY t.name;
-- esperado: 11 linhas no resultado, coluna `linhas` toda zerada
