-- =====================================================================
-- Projeto: Análise Financeira E-commerce Olist
-- Arquivo: 03_load_additional_tables.sql
-- Objetivo: Criar e carregar 3 tabelas operacionais adicionais
--          (products, product_category_translation, sellers) pra dar
--          suporte às dimensões do star schema.
-- =====================================================================

USE olist_financeiro;
GO


-- ---------------------------------------------------------------------
-- TABELA: products
-- ---------------------------------------------------------------------
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

BULK INSERT products
FROM 'C:\Users\Lustosa\OneDrive\Desktop\PORTFÓLIO\projeto_olist_financeiro\dados\olist_products_dataset.csv'
WITH (
    FORMAT = 'CSV',
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '0x0a',
    CODEPAGE = '65001',
    TABLOCK
);


-- ---------------------------------------------------------------------
-- TABELA: product_category_translation
-- Mapa de categoria PT -> EN
-- ---------------------------------------------------------------------
CREATE TABLE product_category_translation (
    product_category_name         VARCHAR(100) NOT NULL,
    product_category_name_english VARCHAR(100),

    CONSTRAINT PK_category_translation PRIMARY KEY (product_category_name)
);

BULK INSERT product_category_translation
FROM 'C:\Users\Lustosa\OneDrive\Desktop\PORTFÓLIO\projeto_olist_financeiro\dados\product_category_name_translation.csv'
WITH (
    FORMAT = 'CSV',
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '0x0a',
    CODEPAGE = '65001',
    TABLOCK
);


-- ---------------------------------------------------------------------
-- TABELA: sellers
-- ---------------------------------------------------------------------
CREATE TABLE sellers (
    seller_id              VARCHAR(50) NOT NULL,
    seller_zip_code_prefix VARCHAR(10),
    seller_city            VARCHAR(100),
    seller_state           CHAR(2),

    CONSTRAINT PK_sellers PRIMARY KEY (seller_id)
);

BULK INSERT sellers
FROM 'C:\Users\Lustosa\OneDrive\Desktop\PORTFÓLIO\projeto_olist_financeiro\dados\olist_sellers_dataset.csv'
WITH (
    FORMAT = 'CSV',
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '0x0a',
    CODEPAGE = '65001',
    TABLOCK
);


-- ---------------------------------------------------------------------
-- Validação
-- ---------------------------------------------------------------------
SELECT 'products'                     AS tabela, COUNT(*) AS total FROM products
UNION ALL
SELECT 'product_category_translation', COUNT(*) FROM product_category_translation
UNION ALL
SELECT 'sellers',                      COUNT(*) FROM sellers;
