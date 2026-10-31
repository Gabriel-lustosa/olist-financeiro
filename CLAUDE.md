# Olist Financeiro — regras para o agente

Projeto de portfólio de BI (SQL Server → SSIS → SSAS Tabular → Power BI) sobre o dataset público Olist.
Objetivo de negócio: diagnosticar a retenção de ~3% (ver `README.md`).

## Estrutura
- `01_sql/` — pipeline do DW em SQL (01–04) e gabarito das análises (05). É a referência de verdade dos números.
- `02_ssis/` — projeto `olist_etl` (pacotes `01_staging`, `02_dimensoes`, `03_fato`, `00_master`) + `00_preparar_banco_ssis.sql`.
- `03_ssas/` — projeto SSAS Tabular `olist_tabular` (etapa 6, em andamento; roteiro abaixo).
- `04_powerbi/` — `olist_financeiro.pbix` e `medidas_dax.md` (fonte da verdade das medidas DAX; atualizar ao criar/alterar medida).
- `dados/` — CSVs do Kaggle, fora do Git.

## Bancos (SQL Server local, instância padrão `localhost`)
- `olist_financeiro` — **DW oficial**, alimenta o Power BI. Nunca alterar dados ou estrutura sem confirmação explícita.
- `olist_financeiro_ssis` — banco de teste do SSIS. Pode ser recriado do zero com `02_ssis/00_preparar_banco_ssis.sql`.
- Collation `Latin1_General_CI_AS` (code page 1252): colunas texto são `VARCHAR`.

## Ambiente e pegadinhas conhecidas
- `sqlcmd`: usar `-S localhost -E -C` (certificado do ODBC 18) e `-f 65001` quando o `.sql` tiver acento (o caminho do repositório tem "PORTFÓLIO"). Rodar pelo PowerShell; no Git Bash o `-E` conflita com variáveis de ambiente.
- SSIS: conexão OLE DB com **Microsoft OLE DB Driver 18 (`MSOLEDBSQL`)**. O Driver 19 dá "provedor não tem suporte" no designer.
- DTExec fora do Visual Studio exige o recurso **Integration Services** instalado no SQL Server (sem ele: erro `0xC000F427`). Rodar a partir do `.ispac` em `bin/Development/` (recompilar após mexer nos pacotes).
- DTExec com `.ispac`: trocar parâmetro de projeto com `/Set '\Package.Variables[$Project::PastaDados];<valor>'`. O `/Par` só funciona com `/ISServer` (SSISDB).
- SSAS: instância padrão Tabular em `localhost` (serviço `MSSQLServerOLAPService`). O modelo implantado processa com a conta `NT Service\MSSQLServerOLAPService` (personificação "Conta de serviço"), que precisa de login no SQL Server, senão dá "Falha de logon". Aplicado em 2026-10-28 com autorização do usuário: `CREATE LOGIN ... FROM WINDOWS` + `CREATE USER` + `db_datareader` no `olist_financeiro` (só leitura). Ao recriar o ambiente, refazer.
- SSAS: a fonte de dados usa `EncryptConnection: false` (o SQL local tem certificado autoassinado; o VS pergunta em "Suporte a Criptografia"). Arquivo `Model.bim_<usuário>.settings` é pessoal (porta do workspace integrado) e fica no `.gitignore`.
- SSAS: o Ctrl+S só grava o `Model.bim`; validar sempre no `localhost` depois de **Implantar** (ADOMD do SSMS 22). O workspace integrado não aceita conexão de fora. Conferir se `bin/Model.asdatabase` é mais novo que o `Model.bim`: se não for, o Implantar mandou o pacote velho. **Recompilar** dá erro `O destino "EntityClean" não existe no projeto` e deixa o VS sem compilar: fechar e reabrir o VS e usar **Compilar** + **Implantar**.
- SSAS: com a coluna selecionada na grade, a barra de fórmulas pode apagar a expressão da coluna calculada sem aviso (aconteceu com `DimData[AnoMes]` na 6.2). Conferir `"expression"` no `Model.bim` antes de commitar.
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

## Etapa 6 — SSAS Tabular (roteiro)
O modelo do Power BI vira um banco no SSAS; `04_powerbi/medidas_dax.md` é o roteiro e o gabarito. Fonte: DW oficial `olist_financeiro`, só leitura; importar só as 5 tabelas do star schema.

| Aula | O quê | Status |
|---|---|---|
| 6.1 | Projeto `olist_tabular` em `03_ssas/` (workspace integrado, compatibilidade mais alta do SQL 2025), importar DimCliente/DimData/DimProduto/DimVendedor/FatoVendas (personificação: conta do serviço), 4 relacionamentos Fato → Dims, implantar em `localhost` | Pronta (`dd3596d`, `2ef6ecf`) |
| 6.2 | 10 colunas calculadas + tabela `Meses Relativos` + "Classificar por coluna" | Pronta |
| 6.3 | 16 medidas + formatos, validadas contra o gabarito | Próxima |
| 6.4 | Acabamento: ocultar SKs/colunas técnicas, hierarquia de datas, pastas de medidas | — |
| 6.5 | Conectar um relatório ao SSAS (provar o modelo fora do Visual Studio) | — |
| 6.6 | README + tópicos `ssas` e `ssas-tabular` no About do GitHub | — |

## Validação
- Toda carga nova é comparada com o DW SQL: contagem + `EXCEPT` nos dois sentidos (esperado 0/0) + totais financeiros.
- Scripts de teste vão para uma pasta temporária, não para o repositório.

## Git
- Mensagens em português, verbo no início, explicando o porquê; um commit por etapa lógica (não misturar correção de SQL com aula de SSIS).
- Commits só com o e-mail noreply do GitHub (o push com outro e-mail é bloqueado).
- Antes de commitar: `git status`, conferir `.gitignore` e tamanho dos arquivos (o `.pbix` tem ~12 MB; agrupar ajustes nele).
- Push direto na `main` (projeto solo).
