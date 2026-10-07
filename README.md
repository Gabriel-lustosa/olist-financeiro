# Projeto Olist — Análise Financeira

Projeto de portfólio em **Business Intelligence** usando o dataset público **Olist** (e-commerce brasileiro, 2016–2018) para investigar performance financeira e retenção de clientes.

> **Headline da análise:**
> **94,4% da receita realizada do Olist vem de clientes que compraram uma única vez.**
> Em um mercado onde adquirir cliente novo custa 5–7× mais que reter, isso é a maior alavanca de crescimento escondida nos dados.

---

## Objetivo de negócio

Diagnosticar o problema de **retenção de ~3%** do e-commerce Olist e identificar alavancas de crescimento a partir de análise financeira, comportamental e geográfica.

---

## Insights-chave

| # | Descoberta | Como foi medido |
|---|---|---|
| 1 | **94,4% da receita vem de clientes one-shot** (R$ 14,5M de R$ 15,4M) | Classificação por `DISTINCTCOUNT(order_id)` sobre pedidos `delivered`, grupado por `customer_unique_id` |
| 2 | 🚧 Curva de retenção mensal (coorte) | Em construção — Lição 5 |
| 3 | 🚧 Decomposição de receita por categoria | Planejado |
| 4 | 🚧 Padrão geográfico de recorrência | Planejado |

---

## Stack técnica

| Camada | Ferramenta | Papel |
|---|---|---|
| Data Warehouse | **SQL Server** | Star schema, carga via BULK INSERT |
| ETL | **SSIS** | Pipeline dos CSVs para o DW |
| Modelo semântico | **SSAS Tabular** | Medidas DAX e hierarquias |
| Visualização | **Power BI** | Dashboard final |

---

## Modelo dimensional (star schema)

```
                 ┌──────────────┐
                 │   DimData    │  (1.096 linhas, 2016–2018)
                 └──────┬───────┘
                        │
┌──────────────┐        │        ┌──────────────┐
│  DimCliente  │────┐   │   ┌────│  DimProduto  │
│   (99.441)   │    │   │   │    │   (32.951)   │
└──────────────┘    ▼   ▼   ▼    └──────────────┘
                 ┌────────────────┐
                 │   FatoVendas   │  (112.650 linhas)
                 │  grão: item    │
                 └────────────────┘
                        ▲
                 ┌──────┴───────┐
                 │ DimVendedor  │  (3.095)
                 └──────────────┘
```

**Métrica âncora:** Receita bruta total = **R$ 15.843.553,24** (`SUM(valor_total)` em FatoVendas)
**Receita realizada** (só pedidos `delivered`): **~R$ 15.364.000** — é essa que entra na análise de retenção.

---

## Como rodar

### Pré-requisitos
- SQL Server 2019+ com SSMS
- Power BI Desktop (versão de outubro/2024 ou mais recente)
- Baixar os 9 CSVs do [Kaggle](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) e colocar em `dados/`

### Ordem dos scripts (`01_sql/`)
```sql
-- 1) Criar banco + 6 tabelas operacionais (staging)
01_create_tables.sql

-- 2) BULK INSERT dos 6 CSVs principais
02_load_data.sql

-- 3) Criar + carregar products, product_category_translation, sellers
03_load_additional_tables.sql

-- 4) Criar dimensões + FatoVendas (com lookup de SKs)
04_create_dimensions.sql
```

Validação final após rodar todos:
```sql
SELECT COUNT(*) FROM FatoVendas;        -- esperado: 112.650
SELECT SUM(valor_total) FROM FatoVendas; -- esperado: 15.843.553,24
```

---

## Estrutura do repositório

```
projeto_olist_financeiro/
├── 01_sql/          Scripts de criação, carga e análise (SQL Server)
├── 02_ssis/         Pacotes de ETL (em construção)
├── 03_ssas/         Modelo tabular (em construção)
├── 04_powerbi/      Relatório .pbix (em construção)
├── dados/           CSVs Olist (não versionado — baixar do Kaggle)
└── README.md
```

---

## Habilidades demonstradas

- **Modelagem dimensional** — star schema com surrogate keys, chaves degeneradas, dimensão de data gerada por CTE recursiva, coluna calculada persistida (`valor_total`)
- **SQL avançado** — BULK INSERT com `CODEPAGE 65001` (UTF-8), lookup de SKs via INNER JOIN, CTE recursiva, validações `COUNT(*)`/`SUM()` origem vs. destino
- **DAX** — colunas calculadas com `VAR` + `CALCULATE` + `FILTER(ALL(...))` pra escapar do contexto de linha, medidas de retenção por coorte, divisão segura com `DIVIDE`
- **Análise de retenção** — classificação one-shot vs. recorrente, curva de coorte mensal, decomposição de receita
- **Documentação** — scripts com cabeçalho, convenções explícitas, comentários sobre pegadinhas do dataset (`customer_id` vs. `customer_unique_id`)

---

## Dashboards

🚧 Em construção. Screenshots e link do relatório publicado serão adicionados após conclusão das lições de modelagem semântica.

---

## Status

| Etapa | Status |
|---|---|
| DW no SQL Server | ✅ Pronto |
| Star schema carregado | ✅ 112.650 linhas em FatoVendas |
| Pacotes SSIS | 🚧 Em construção |
| Modelo SSAS Tabular | 🚧 Em construção |
| Dashboard Power BI | 🚧 Em construção (Lição 5 — análise de coorte) |

---

## Dataset

Os 9 CSVs **não estão** neste repositório (dataset público, >100 MB).
Download: https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce

---

*Projeto desenvolvido por [Gabriel Lustosa](https://github.com/Gabriel-lustosa) como portfólio pessoal de BI/Analytics.*
