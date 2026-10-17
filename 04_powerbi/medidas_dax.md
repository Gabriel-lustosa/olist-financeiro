# Medidas e colunas DAX — `olist_financeiro.pbix`

Todo o DAX do modelo, com o porquê de cada fórmula e o valor esperado.
Cada número abaixo foi **validado contra o SQL Server** (`olist_financeiro`) em 15/10/2026, com diferença de zero centavos.

> O `.pbix` é binário, então o GitHub não mostra o que tem dentro. Este arquivo é a versão legível do modelo.

---

## Modelo e relacionamentos

| De (muitos) | Para (um) | Direção do filtro |
|---|---|---|
| `FatoVendas[sk_cliente]` | `DimCliente[sk_cliente]` | única (Dim → Fato) |
| `FatoVendas[sk_produto]` | `DimProduto[sk_produto]` | única |
| `FatoVendas[sk_vendedor]` | `DimVendedor[sk_vendedor]` | única |
| `FatoVendas[sk_data]` | `DimData[sk_data]` | única |

**Duas pegadinhas que guiam quase todo o DAX abaixo:**

1. **`customer_id` ≠ pessoa.** No Olist, cada pedido gera um `customer_id` novo. Quem identifica a pessoa é o `customer_unique_id`. Como o relacionamento é por `sk_cliente` (que segue o `customer_id`), qualquer conta "por pessoa" precisa **ampliar o filtro** para todas as linhas da DimCliente com o mesmo `customer_unique_id`.
2. **O filtro só desce (Dim → Fato).** Filtrar a FatoVendas **não** filtra a DimData. Para pegar a data de um pedido a partir da fato, use `RELATED` linha a linha.

---

## Medidas (`_Medidas`)

### Receita

```DAX
Receita total = SUM( FatoVendas[valor_total] )
```
Soma de `price + freight_value` de todos os itens, **em qualquer status**. → **R$ 15.843.553,24**

```DAX
Receita Realizada =
    CALCULATE(
        [Receita Total],
        FatoVendas[order_status] = "delivered" )
```
Só pedidos **entregues**: é a receita que de fato entrou. Base de toda a análise de retenção. → **R$ 15.419.773,75**

### Pedidos e ticket

```DAX
Total de Pedidos =
    CALCULATE(
        DISTINCTCOUNT( FatoVendas[order_id] ),
        FatoVendas[order_status] = "delivered" )
```
`DISTINCTCOUNT` porque o grão da fato é **item**: um pedido com 3 itens tem 3 linhas. → **96.478**

```DAX
Ticket Médio = DIVIDE( [Receita Realizada], [Total de Pedidos] )
```
`DIVIDE` em vez de `/` evita erro de divisão por zero em filtros vazios. → **R$ 159,83**

### Clientes e retenção

```DAX
Clientes Únicos =
    COUNTROWS(
        SUMMARIZE(
            CALCULATETABLE( FatoVendas, FatoVendas[order_status] = "delivered" ),
            DimCliente[customer_unique_id] ) )
```
Pessoas distintas com pelo menos um pedido entregue. O `SUMMARIZE` agrupa os itens entregues por pessoa, e o `COUNTROWS` conta os grupos. → **93.358**

```DAX
Clientes Recorrentes =
    COUNTROWS(
        FILTER(
            ADDCOLUMNS(
                SUMMARIZE(
                    CALCULATETABLE( FatoVendas, FatoVendas[order_status] = "delivered" ),
                    DimCliente[customer_unique_id]
                ),
                "QtdPedidos",
                CALCULATE(
                    DISTINCTCOUNT( FatoVendas[order_id] ),
                    FatoVendas[order_status] = "delivered"
                )
            ),
            [QtdPedidos] > 1
        )
    )
```
Monta uma tabela virtual "pessoa × qtd de pedidos entregues" e conta quem tem mais de 1. → **2.801**

```DAX
Taxa de Retenção = DIVIDE( [Clientes Recorrentes], [Clientes Únicos] )
```
→ **3,0%** (2.801 de 93.358)

### Receita por tipo de cliente (tese central)

```DAX
Receita One-shot     = CALCULATE( [Receita Realizada], DimCliente[Tipo Cliente] = "Único" )
Receitas Recorrentes = CALCULATE( [Receita Realizada], DimCliente[Tipo Cliente] = "Recorrente" )
% Receitas One-shot  = DIVIDE( [Receita One-shot], [Receita Realizada] )
```

| Medida | Valor |
|---|---|
| Receita One-shot | **R$ 14.555.586,29** |
| Receitas Recorrentes | **R$ 864.187,46** |
| Soma (= Receita Realizada) | R$ 15.419.773,75 ✅ |
| **% Receitas One-shot** | **94,4%** |

### Retenção por coorte

```DAX
Tamanho Coorte =
    CALCULATE( [Clientes Únicos], REMOVEFILTERS( DimData ) )
```
Quantas pessoas a coorte tem. O `REMOVEFILTERS(DimData)` impede que um filtro de data encolha a coorte.

```DAX
Clientes Ativos Coorte =
    VAR K = SELECTEDVALUE( 'Meses Relativos'[Mes Relativo] )
    RETURN
        IF( NOT ISBLANK( K ),
            SUMX(
                VALUES( DimCliente[Aquisicao Mes Indice] ),
                VAR Coorte = DimCliente[Aquisicao Mes Indice]
                RETURN
                    CALCULATE(
                        [Clientes Únicos],
                        DimData[Mes Indice] = Coorte + K ) ) )
```
- `K` vem da tabela desconectada `Meses Relativos` (a coluna da matriz).
- O `SUMX` percorre as coortes do contexto (uma por linha da matriz; todas num total).
- Para cada coorte, o `CALCULATE` faz a transição de contexto (prende a contagem às pessoas da coorte) e troca o filtro de data para o mês `Coorte + K`. O `[Clientes Únicos]` é reaproveitado.

```DAX
% Retenção Coorte = DIVIDE( [Clientes Ativos Coorte], [Tamanho Coorte] )
```

Validado contra a seção 5 do `05_analise_recorrencia.sql`: **219 de 219 células iguais**, 23 coortes somando **93.358** pessoas.

| Coorte | Tamanho | Mês 1 | Mês 2 | Mês 3 |
|---|---|---|---|---|
| 2017-08 | 4.057 | 0,69% | 0,35% | 0,27% |
| 2017-11 | 7.060 | 0,57% | 0,37% | 0,17% |
| 2018-01 | 6.842 | 0,34% | 0,37% | 0,29% |
| 2018-04 | 6.582 | 0,59% | 0,30% | 0,24% |

### Formatos

O formato fica **na medida**, não no visual: assim qualquer cartão, tabela ou gráfico já mostra o número do jeito certo.

| Medida | Formato |
|---|---|
| Receita total, Receita Realizada, Receita One-shot, Receitas Recorrentes, Ticket Médio | Moeda R$ (Português – Brasil), 2 casas |
| Total de Pedidos, Clientes Únicos, Clientes Recorrentes, Tamanho Coorte, Clientes Ativos Coorte | Número inteiro |
| Taxa de Retenção, % Receitas One-shot | Porcentagem, 1 casa |
| % Retenção Coorte | Porcentagem, 2 casas (os valores ficam abaixo de 1%) |

---

## Página "Visão Geral"

Manchete com a tese + 4 cartões que a comprovam:

| Cartão | Medida | Exibe |
|---|---|---|
| 1 | `[Receita One-shot]` | R$ 14,56 Mi |
| 2 | `[Receitas Recorrentes]` | R$ 864,19 Mil |
| 3 | `[% Receitas One-shot]` | 94,4% |
| 4 | `[Taxa de Retenção]` | 3,0% |

## Página "Retenção por Coorte"

Manchete: *Menos de 1% dos clientes volta a comprar em qualquer mês após a 1ª compra.*

Matriz: **Linhas** `DimCliente[AnoMes Aquisicao]` · **Colunas** `Meses Relativos[Mes Relativo]` · **Valores** `[% Retenção Coorte]`.

- Filtro no visual: `Mes Relativo >= 1` (o mês 0 é sempre 100% e apagaria a escala de cor).
- Subtotais de linha e de coluna desligados: a média distorce, porque as coortes recentes ainda não tiveram tempo de voltar.
- Mapa de calor: gradiente de **0** (branco) a **0,01 = 1%** (`#B03A2E`), com máximo fixo para as coortes de 2016 (1 pessoa só) não dominarem a escala.

---

## Colunas calculadas

### `DimCliente[Qtd Pedidos Entregues]`

```DAX
Qtd Pedidos Entregues =
    CALCULATE(
        DISTINCTCOUNT( FatoVendas[order_id] ),
        ALLEXCEPT( DimCliente, DimCliente[customer_unique_id] ),
        FatoVendas[order_status] = "delivered" )
```
- O `CALCULATE` numa coluna faz **transição de contexto**: filtra a linha atual.
- O `ALLEXCEPT` tira esse filtro de todas as colunas **menos** `customer_unique_id`, ou seja, junta todas as linhas da mesma pessoa.
- Em branco = pessoa que nunca recebeu um pedido.

> ⚠️ **Versão antiga (evitar):** `FILTER( ALL(DimCliente), DimCliente[customer_unique_id] = CUID )` dá o mesmo resultado, mas percorre as 99.441 linhas para cada uma das 99.441 linhas (cerca de 10 bilhões de comparações) e **travava o Power BI**.

| Pedidos entregues | Pessoas |
|---|---|
| (em branco) | 2.738 |
| 1 | 90.557 |
| 2 | 2.573 |
| 3 | 181 |
| 4 a 15 | 47 |
| **Total** | **96.096** |

### `DimCliente[Tipo Cliente]`

```DAX
Tipo Cliente = IF( DimCliente[Qtd Pedidos Entregues] > 1, "Recorrente", "Único" )
```
→ Recorrente: **2.801** · Único: **93.295** (inclui os 2.738 sem entrega)

### `DimCliente[AnoMes Aquisicao Numero]` e `[AnoMes Aquisicao]`

Mês da **primeira compra entregue** de cada pessoa: a base da análise de coorte.

```DAX
AnoMes Aquisicao Numero =
    VAR DataPrimeiraCompra =
        CALCULATE(
            MINX( FatoVendas, RELATED( DimData[data_completa] ) ),
            ALLEXCEPT( DimCliente, DimCliente[customer_unique_id] ),
            FatoVendas[order_status] = "delivered"
        )
    RETURN
        IF( ISBLANK( DataPrimeiraCompra ), BLANK(),
            YEAR( DataPrimeiraCompra ) * 100 + MONTH( DataPrimeiraCompra ) )
```

```DAX
AnoMes Aquisicao =
    VAR N = DimCliente[AnoMes Aquisicao Numero]
    RETURN
        IF( ISBLANK( N ), BLANK(),
            FORMAT( DATE( INT( N / 100 ), MOD( N, 100 ), 1 ), "YYYY-MM" ) )
```

> 🐛 **Bug corrigido (commit `3bb3581`):** a versão anterior usava `MIN( DimData[data_completa] )`. Como o filtro não sobe da FatoVendas para a DimData, o MIN devolvia a primeira data do calendário e **todas as 96.096 pessoas ficavam com 201601**. O `MINX` sobre a FatoVendas com `RELATED` resolve.

Resultado: 23 meses, de 2016-09 a 2018-08, com **93.358** pessoas com data e **2.738** em branco. O pico é **2017-11** (Black Friday), com **7.060** novos clientes.

### `DimData[AnoMes]` e `[AnoMes Numero]`

```DAX
AnoMes        = FORMAT( DimData[data_completa], "YYYY-MM" )
AnoMes Numero = YEAR( DimData[data_completa] ) * 100 + MONTH( DimData[data_completa] )
```
Nos dois pares (`AnoMes` e `AnoMes Aquisicao`), a coluna de texto está configurada com **Classificar por coluna** apontando para a versão `Numero`. Assim os meses ficam em ordem cronológica nos visuais, sem depender da ordem alfabética do texto.

### `DimData[Mes Indice]` e `DimCliente[Aquisicao Mes Indice]`

```DAX
Mes Indice = YEAR( DimData[data_completa] ) * 12 + MONTH( DimData[data_completa] )
```

```DAX
Aquisicao Mes Indice =
    VAR N = DimCliente[AnoMes Aquisicao Numero]
    RETURN
        IF( ISBLANK( N ), BLANK(),
            INT( N / 100 ) * 12 + MOD( N, 100 ) )
```
Os meses viram números consecutivos para que a distância entre dois meses seja uma subtração: com AAAAMM, `201801 − 201711 = 90`; com o índice, `24.217 − 24.215 = 2`. Base da medida `[Clientes Ativos Coorte]`.

---

## Tabelas calculadas

### `Meses Relativos`

```DAX
Meses Relativos =
    SELECTCOLUMNS( GENERATESERIES( 0, 20, 1 ), "Mes Relativo", [Value] )
```
Régua de 0 a 20 ("meses depois da aquisição"; 20 é a maior distância nos dados). **Desconectada de propósito**: não tem relacionamento; só desenha as colunas da matriz e a medida lê o valor com `SELECTEDVALUE`.
