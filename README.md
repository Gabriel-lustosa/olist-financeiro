# Projeto Olist — Análise Financeira

Projeto de portfólio em Business Intelligence usando o dataset público **Olist** (e-commerce brasileiro, 2016-2018) para investigar performance financeira e retenção de clientes.

## Objetivo de negócio

Diagnosticar o problema de **retenção de 3%** do e-commerce Olist e identificar alavancas de crescimento a partir de análise financeira, comportamental e geográfica.

## Stack

- **SQL Server** — Data Warehouse (star schema)
- **SSIS** — ETL dos CSVs para o DW
- **SSAS Tabular** — Modelo semântico
- **Power BI** — Dashboard final

## Estrutura

```
projeto_olist_financeiro/
├── 01_sql/          Scripts de criação, carga e análise
├── 02_ssis/         Pacotes de ETL
├── 03_ssas/         Modelo tabular
├── 04_powerbi/      Relatório .pbix
├── dados/           CSVs Olist (não versionado — baixar do Kaggle)
└── docs/            Insights e documentação
```

## Dataset

Os CSVs **não estão** neste repositório (100+ MB, dataset público).
Baixar em: https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce

Colocar os 9 arquivos `.csv` na pasta `dados/` antes de rodar os scripts.

## Modelo dimensional

- **FatoVendas** (112.650 linhas)
- **DimCliente** (99.441)
- **DimProduto** (32.951)
- **DimVendedor** (3.095)
- **DimData** (1.096, 2016-2018)

Métrica âncora: **Receita total R$ 15.843.553,24**

## Status

🚧 Em desenvolvimento — construção do dashboard Power BI em andamento.
