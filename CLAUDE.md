# Olist Financeiro — regras para o agente

Projeto de portfólio de BI (SQL Server → SSIS → SSAS Tabular → Power BI) sobre o dataset público Olist.
Objetivo de negócio: diagnosticar a retenção de ~3% (ver `README.md`).

## Estrutura
- `01_sql/` — pipeline do DW em SQL (01–04) e gabarito das análises (05). É a referência de verdade dos números.
- `02_ssis/` — projeto `olist_etl` (pacotes `01_staging`, `02_dimensoes`, `03_fato`, `00_master`) + `00_preparar_banco_ssis.sql`.
- `03_ssas/` — modelo SSAS Tabular (ainda não iniciado).
- `04_powerbi/` — `olist_financeiro.pbix` e `medidas_dax.md` (fonte da verdade das medidas DAX; atualizar ao criar/alterar medida).
- `dados/` — CSVs do Kaggle, fora do Git.

## Bancos (SQL Server local, instância padrão `localhost`)
- `olist_financeiro` — **DW oficial**, alimenta o Power BI. Nunca alterar dados ou estrutura sem confirmação explícita.
- `olist_financeiro_ssis` — banco de teste do SSIS. Pode ser recriado do zero com `02_ssis/00_preparar_banco_ssis.sql`.
- Collation `Latin1_General_CI_AS` (code page 1252): colunas texto são `VARCHAR`.

## Ambiente e pegadinhas conhecidas
- `sqlcmd`: usar `-S localhost -E -C` (certificado do ODBC 18) e `-f 65001` quando o `.sql` tiver acento (o caminho do repositório tem "PORTFÓLIO"). Rodar pelo PowerShell; no Git Bash o `-E` conflita com variáveis de ambiente.
- SSIS: conexão OLE DB com **Microsoft OLE DB Driver 18 (`MSOLEDBSQL`)**. O Driver 19 dá "provedor não tem suporte" no designer.
- Visual Studio está em português: citar menus e componentes pelo nome em PT (Origem OLE DB, Pesquisa, Coluna Derivada...).
- CSVs: 5 são LF; `product_category_name_translation.csv` é CRLF com BOM; só `olist_sellers_dataset.csv` tem não-ASCII (UTF-8, inclui um til combinante U+0303). Contar bytes CR com `od`, não com `grep`.
- O projeto está no OneDrive: o Visual Studio pode avisar "arquivo alterado externamente".

## Números de referência (validar contra eles)
| Item | Valor |
|---|---|
| customers / orders | 99.441 / 99.441 |
| order_items = linhas da FatoVendas | 112.650 |
| products / sellers / translation | 32.951 / 3.095 / 71 |
| DimData | 1.096 dias (2016-01-01 a 2018-12-31) |
| Receita total (price + frete, todos os status) | R$ 15.843.553,24 |
| Receita realizada (`delivered`) | R$ 15.419.773,75 |

Divergências propositais SSIS × DW SQL: 1 vendedor (`sao paulo` no SSIS × `sa~o paulo` no SQL); SK da DimProduto em ordem diferente (comparar pela NK `product_id`).

## Validação
- Toda carga nova é comparada com o DW SQL: contagem + `EXCEPT` nos dois sentidos (esperado 0/0) + totais financeiros.
- Scripts de teste vão para uma pasta temporária, não para o repositório.

## Git
- Mensagens em português, verbo no início, explicando o porquê; um commit por etapa lógica (não misturar correção de SQL com aula de SSIS).
- Commits só com o e-mail noreply do GitHub (o push com outro e-mail é bloqueado).
- Antes de commitar: `git status`, conferir `.gitignore` e tamanho dos arquivos (o `.pbix` tem ~12 MB; agrupar ajustes nele).
- Push direto na `main` (projeto solo).
