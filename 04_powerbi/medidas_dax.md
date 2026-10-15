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
