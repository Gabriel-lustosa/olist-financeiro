-- =====================================================================
-- Projeto: Análise Financeira E-commerce Olist
-- Arquivo: 04_create_dimensions.sql
-- Objetivo: Criar as tabelas DIMENSÃO do Star Schema, com Surrogate Keys.
--          As dimensões guardam o "contexto" (quem, o quê, quando, onde)
--          e serão referenciadas pela tabela FATO via SK.
-- =====================================================================

USE olist_financeiro;
GO


-- ---------------------------------------------------------------------
-- DIMENSÃO: DimVendedor
-- Origem: tabela operacional `sellers`
--
-- Estrutura padrão de toda dimensão:
--   1) sk_xxx   -> Surrogate Key (INT IDENTITY, PK do DW)
--   2) NK       -> chave do sistema origem (preservada p/ rastreabilidade)
--   3) atributos descritivos
-- ---------------------------------------------------------------------
CREATE TABLE DimVendedor (
    sk_vendedor            INT IDENTITY(1,1) NOT NULL,   -- SK gerada pelo DW
    seller_id              VARCHAR(50)       NOT NULL,   -- NK (vem do Olist)
    seller_zip_code_prefix VARCHAR(10),
    seller_city            VARCHAR(100),
    seller_state           CHAR(2),

    CONSTRAINT PK_DimVendedor PRIMARY KEY (sk_vendedor),
    CONSTRAINT UQ_DimVendedor_seller_id UNIQUE (seller_id)
);


-- ---------------------------------------------------------------------
-- Carga da DimVendedor a partir de `sellers`
-- IDENTITY cuida do sk_vendedor automaticamente, então NÃO listamos ele
-- ---------------------------------------------------------------------
INSERT INTO DimVendedor (
    seller_id,
    seller_zip_code_prefix,
    seller_city,
    seller_state
)
SELECT
    seller_id,
    seller_zip_code_prefix,
    seller_city,
    seller_state
FROM sellers;


-- ---------------------------------------------------------------------
-- Validação DimVendedor
-- ---------------------------------------------------------------------
SELECT TOP 10 * FROM DimVendedor ORDER BY sk_vendedor;

SELECT
    (SELECT COUNT(*) FROM sellers)      AS total_origem,
    (SELECT COUNT(*) FROM DimVendedor)  AS total_dimensao;


-- ---------------------------------------------------------------------
-- DIMENSÃO: DimProduto
-- Origem: tabela operacional `products` + LEFT JOIN com
--         `product_category_translation` para DENORMALIZAR a tradução
--         da categoria (PT -> EN) dentro da própria dimensão.
--
-- LEFT JOIN: alguns produtos podem não ter categoria mapeada na
-- tabela de tradução — nesse caso o campo em inglês fica NULL,
-- mas o produto NÃO é descartado.
-- ---------------------------------------------------------------------
CREATE TABLE DimProduto (
    sk_produto                    INT IDENTITY(1,1) NOT NULL,   -- SK do DW
    product_id                    VARCHAR(50)       NOT NULL,   -- NK (Olist)
    product_category_name         VARCHAR(100),                 -- categoria PT
    product_category_name_english VARCHAR(100),                 -- categoria EN (denormalizado)
    product_weight_g              INT,
    product_length_cm             INT,
    product_height_cm             INT,
    product_width_cm              INT,

    CONSTRAINT PK_DimProduto PRIMARY KEY (sk_produto),
    CONSTRAINT UQ_DimProduto_product_id UNIQUE (product_id)
);


-- ---------------------------------------------------------------------
-- Carga da DimProduto
-- ---------------------------------------------------------------------
INSERT INTO DimProduto (
    product_id,
    product_category_name,
    product_category_name_english,
    product_weight_g,
    product_length_cm,
    product_height_cm,
    product_width_cm
)
SELECT
    p.product_id,
    p.product_category_name,
    t.product_category_name_english,
    p.product_weight_g,
    p.product_length_cm,
    p.product_height_cm,
    p.product_width_cm
FROM products AS p
LEFT JOIN product_category_translation AS t
       ON p.product_category_name = t.product_category_name;


-- ---------------------------------------------------------------------
-- Validação DimProduto
-- ---------------------------------------------------------------------
SELECT TOP 10 * FROM DimProduto ORDER BY sk_produto;

SELECT
    (SELECT COUNT(*) FROM products)    AS total_origem,
    (SELECT COUNT(*) FROM DimProduto)  AS total_dimensao;


-- ---------------------------------------------------------------------
-- DIMENSÃO: DimCliente
-- Origem: tabela operacional `customers`
--
-- ATENÇÃO Olist: customer_id muda a cada pedido (sessão de compra);
-- customer_unique_id identifica a pessoa real. Usamos customer_id
-- como NK porque a tabela `orders` referencia esse; o unique_id
-- vai como atributo p/ análises de "cliente recorrente".
-- ---------------------------------------------------------------------
CREATE TABLE DimCliente (
    sk_cliente               INT IDENTITY(1,1) NOT NULL,   -- SK do DW
    customer_id              VARCHAR(50)       NOT NULL,   -- NK (Olist)
    customer_unique_id       VARCHAR(50),                  -- ID da pessoa real
    customer_zip_code_prefix VARCHAR(10),
    customer_city            VARCHAR(100),
    customer_state           CHAR(2),

    CONSTRAINT PK_DimCliente PRIMARY KEY (sk_cliente),
    CONSTRAINT UQ_DimCliente_customer_id UNIQUE (customer_id)
);


-- ---------------------------------------------------------------------
-- Carga da DimCliente
-- ---------------------------------------------------------------------
INSERT INTO DimCliente (
    customer_id,
    customer_unique_id,
    customer_zip_code_prefix,
    customer_city,
    customer_state
)
SELECT
    customer_id,
    customer_unique_id,
    customer_zip_code_prefix,
    customer_city,
    customer_state
FROM customers;


-- ---------------------------------------------------------------------
-- Validação DimCliente
-- ---------------------------------------------------------------------
SELECT TOP 10 * FROM DimCliente ORDER BY sk_cliente;

SELECT
    (SELECT COUNT(*) FROM customers)   AS total_origem,
    (SELECT COUNT(*) FROM DimCliente)  AS total_dimensao;


-- ---------------------------------------------------------------------
-- DIMENSÃO: DimData
-- Origem: NENHUMA tabela — gerada artificialmente via CTE recursiva.
--
-- SK inteligente: formato YYYYMMDD (ex: 20180415). Única, ordenável,
-- legível. Convenção de mercado pra DimData.
--
-- Range: 2016-01-01 a 2018-12-31 (cobre orders 2016-09 a 2018-10
-- com folga p/ análises YTD/YoY).
-- ---------------------------------------------------------------------
CREATE TABLE DimData (
    sk_data          INT          NOT NULL,   -- YYYYMMDD
    data_completa    DATE         NOT NULL,
    ano              INT          NOT NULL,
    trimestre        INT          NOT NULL,   -- 1..4
    mes_numero       INT          NOT NULL,   -- 1..12
    mes_nome         VARCHAR(20)  NOT NULL,   -- 'Janeiro', 'Fevereiro'...
    dia              INT          NOT NULL,   -- 1..31
    dia_semana_num   INT          NOT NULL,   -- 1=Domingo .. 7=Sábado (padrão SQL Server)
    dia_semana_nome  VARCHAR(20)  NOT NULL,   -- 'Segunda-feira'...
    eh_fim_semana    BIT          NOT NULL,   -- 1=sábado/domingo, 0=dia útil

    CONSTRAINT PK_DimData PRIMARY KEY (sk_data)
);


-- ---------------------------------------------------------------------
-- Carga da DimData via CTE recursiva
-- ---------------------------------------------------------------------
-- Pra exibir nomes em português (mês/dia da semana)
SET LANGUAGE 'Brazilian';

WITH calendario AS (
    -- âncora: primeira data do range
    SELECT CAST('2016-01-01' AS DATE) AS data_completa
    UNION ALL
    -- recursão: soma 1 dia até chegar no fim
    SELECT DATEADD(DAY, 1, data_completa)
    FROM calendario
    WHERE data_completa < '2018-12-31'
)
INSERT INTO DimData (
    sk_data,
    data_completa,
    ano,
    trimestre,
    mes_numero,
    mes_nome,
    dia,
    dia_semana_num,
    dia_semana_nome,
    eh_fim_semana
)
SELECT
    CAST(CONVERT(VARCHAR(8), data_completa, 112) AS INT)  AS sk_data,  -- YYYYMMDD
    data_completa,
    YEAR(data_completa),
    DATEPART(QUARTER, data_completa),
    MONTH(data_completa),
    DATENAME(MONTH, data_completa),
    DAY(data_completa),
    DATEPART(WEEKDAY, data_completa),
    DATENAME(WEEKDAY, data_completa),
    CASE WHEN DATEPART(WEEKDAY, data_completa) IN (1, 7) THEN 1 ELSE 0 END
FROM calendario
OPTION (MAXRECURSION 0);   -- libera o limite padrão de 100 da CTE recursiva


-- ---------------------------------------------------------------------
-- Validação DimData
-- ---------------------------------------------------------------------
SELECT TOP 10 * FROM DimData ORDER BY sk_data;

SELECT
    COUNT(*)            AS total_dias,
    MIN(data_completa)  AS data_min,
    MAX(data_completa)  AS data_max
FROM DimData;
-- esperado: 1096 dias (2016=366 + 2017=365 + 2018=365)


-- =====================================================================
-- TABELA FATO: FatoVendas
-- =====================================================================
-- Grão: 1 linha por (order_id, order_item_id) — um item dentro do pedido.
-- Conceitos aplicados:
--   * Lookup de SK: cada FK na fato vem de um JOIN com a respectiva
--     dimensão, pra trocar a NK do sistema origem pela SK do DW.
--   * Chave degenerada: order_id e order_item_id ficam no fato sem
--     dimensão própria — só p/ rastreabilidade.
--   * Medidas aditivas: price, freight_value, valor_total.
-- Data usada: order_purchase_timestamp (evento de receita).
-- =====================================================================
CREATE TABLE FatoVendas (
    -- FKs (todas SKs das dimensões)
    sk_data        INT          NOT NULL,
    sk_cliente     INT          NOT NULL,
    sk_produto     INT          NOT NULL,
    sk_vendedor    INT          NOT NULL,

    -- Chaves degeneradas (NKs sem dimensão própria)
    order_id       VARCHAR(50)  NOT NULL,
    order_item_id  INT          NOT NULL,
    order_status   VARCHAR(20),

    -- Medidas
    price          DECIMAL(10,2) NOT NULL,
    freight_value  DECIMAL(10,2) NOT NULL,
    valor_total    AS (price + freight_value) PERSISTED,   -- coluna calculada

    CONSTRAINT PK_FatoVendas PRIMARY KEY (order_id, order_item_id),

    -- Integridade referencial com as dimensões
    CONSTRAINT FK_FatoVendas_Data     FOREIGN KEY (sk_data)     REFERENCES DimData(sk_data),
    CONSTRAINT FK_FatoVendas_Cliente  FOREIGN KEY (sk_cliente)  REFERENCES DimCliente(sk_cliente),
    CONSTRAINT FK_FatoVendas_Produto  FOREIGN KEY (sk_produto)  REFERENCES DimProduto(sk_produto),
    CONSTRAINT FK_FatoVendas_Vendedor FOREIGN KEY (sk_vendedor) REFERENCES DimVendedor(sk_vendedor)
);


-- ---------------------------------------------------------------------
-- Carga da FatoVendas via lookups das SKs
-- ---------------------------------------------------------------------
-- Cada JOIN abaixo serve pra TROCAR a NK pela SK correspondente.
-- INNER JOIN: se algum item não tiver match em alguma dimensão, fica
-- de fora (proteção contra dados órfãos).
-- ---------------------------------------------------------------------
INSERT INTO FatoVendas (
    sk_data,
    sk_cliente,
    sk_produto,
    sk_vendedor,
    order_id,
    order_item_id,
    order_status,
    price,
    freight_value
)
SELECT
    -- lookup da data: converte timestamp em YYYYMMDD pra bater com sk_data
    CAST(CONVERT(VARCHAR(8), o.order_purchase_timestamp, 112) AS INT) AS sk_data,
    dc.sk_cliente,
    dp.sk_produto,
    dv.sk_vendedor,
    oi.order_id,
    oi.order_item_id,
    o.order_status,
    oi.price,
    oi.freight_value
FROM order_items AS oi
INNER JOIN orders       AS o  ON oi.order_id    = o.order_id
INNER JOIN DimCliente   AS dc ON o.customer_id  = dc.customer_id
INNER JOIN DimProduto   AS dp ON oi.product_id  = dp.product_id
INNER JOIN DimVendedor  AS dv ON oi.seller_id   = dv.seller_id
INNER JOIN DimData      AS dd ON CAST(CONVERT(VARCHAR(8), o.order_purchase_timestamp, 112) AS INT) = dd.sk_data;


-- ---------------------------------------------------------------------
-- Validação FatoVendas
-- ---------------------------------------------------------------------
SELECT TOP 10 * FROM FatoVendas;

SELECT
    (SELECT COUNT(*) FROM order_items) AS total_origem,
    (SELECT COUNT(*) FROM FatoVendas)  AS total_fato;

-- Sanity-check financeiro: receita total e ticket médio
SELECT
    COUNT(*)                AS qtd_itens,
    SUM(price)              AS receita_produtos,
    SUM(freight_value)      AS receita_frete,
    SUM(valor_total)        AS receita_total,
    AVG(valor_total)        AS ticket_medio_item
FROM FatoVendas;
