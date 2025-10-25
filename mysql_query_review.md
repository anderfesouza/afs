# Revisão de Query MySQL - ContaAzulReceitas

## Problemas Identificados na Query Original

### 1. **Subconsultas Correlacionadas Múltiplas (PROBLEMA CRÍTICO)**
- A query executa **6 subconsultas correlacionadas** no SELECT principal
- Cada subconsulta é executada para **cada linha** do resultado do GROUP BY
- Dentro de cada subconsulta, há **outra subconsulta aninhada** (total: 12+ execuções por linha)

**Impacto**: Se o resultado tiver 1000 contratos, a tabela será escaneada ~12.000 vezes!

### 2. **Múltiplas Varreduras da Mesma Tabela**
- A tabela `ContaAzulReceitas` é lida várias vezes:
  - 1x na subquery base `b`
  - 6x nas subconsultas correlacionadas do SELECT
  - Cada subconsulta correlacionada tem outra subconsulta interna

### 3. **Cálculos Redundantes**
- `MIN(vencimento)` para atrasos é calculado 2 vezes
- `MIN(vencimento)` para futuras é calculado 2 vezes
- `MAX(vencimento)` para quitados é calculado 2 vezes

### 4. **Ausência de CTEs**
- Não usa `WITH` para reutilizar cálculos intermediários
- Força o MySQL a recalcular os mesmos valores múltiplas vezes

### 5. **Uso Ineficiente de CASE**
- Cada CASE tem 3 ramos com subconsultas completas
- Poderia ser resolvido com um único JOIN em dados pré-calculados

---

## Query Otimizada

```sql
-- CTE 1: Normalização dos dados base
WITH base_data AS (
  SELECT
    id_cliente,
    nome_cliente,
    id_categoria,
    nome_categoria,
    metodo_pagamento,
    DATE(data_criacao) AS data_compra,
    DATE(vencimento) AS dt_venc,
    COALESCE(nao_pago, 0) AS vl_nao_pago,
    COALESCE(pago, 0) AS vl_pago,
    COALESCE(rateio_valor, 0) AS vl_total,
    NULLIF(quantidade_parcelas, 0) AS qtd_parcelas_contrato,
    CASE WHEN status_traduzido = 'RECEBIDO' THEN 1 ELSE 0 END AS fl_paga,
    CASE WHEN status_traduzido <> 'RECEBIDO' AND COALESCE(nao_pago, 0) > 0 THEN 1 ELSE 0 END AS fl_pendente,
    CASE WHEN COALESCE(nao_pago, 0) > 0 AND DATE(vencimento) < CURDATE() THEN 1 ELSE 0 END AS fl_atrasada,
    CASE WHEN COALESCE(nao_pago, 0) > 0 AND DATE(vencimento) >= CURDATE() THEN 1 ELSE 0 END AS fl_futura_em_aberto
  FROM dagiel67_central_mdzd.ContaAzulReceitas
),

-- CTE 2: Agregações principais
agg_base AS (
  SELECT
    id_cliente,
    nome_cliente,
    id_categoria,
    nome_categoria,
    metodo_pagamento,
    MIN(data_compra) AS Compra,
    SUM(vl_nao_pago) AS Aberto,
    SUM(vl_pago) AS Pago,
    SUM(vl_total) AS Total,
    SUM(fl_pendente) AS Pendentes,
    SUM(fl_paga) AS Pagas,
    COUNT(*) AS Parcelas,
    COALESCE(MAX(qtd_parcelas_contrato), COUNT(*)) AS Total_Parcelas_Contrato,
    MAX(fl_atrasada) AS max_fl_atrasada,
    MAX(fl_futura_em_aberto) AS max_fl_futura_em_aberto,
    CASE
      WHEN MAX(fl_atrasada) = 1 THEN 'Atraso'
      WHEN MAX(fl_futura_em_aberto) = 1 THEN 'Ativo'
      ELSE 'Quitado'
    END AS Status
  FROM base_data
  GROUP BY id_cliente, nome_cliente, id_categoria, nome_categoria, metodo_pagamento
),

-- CTE 3: Vencimentos relevantes (1 scan, calcula tudo de uma vez)
vencimentos_relevantes AS (
  SELECT
    id_cliente,
    id_categoria,
    metodo_pagamento,
    MIN(CASE WHEN fl_atrasada = 1 THEN dt_venc END) AS primeiro_atraso,
    MIN(CASE WHEN fl_futura_em_aberto = 1 THEN dt_venc END) AS proximo_vencimento,
    MAX(dt_venc) AS ultimo_vencimento
  FROM base_data
  GROUP BY id_cliente, id_categoria, metodo_pagamento
),

-- CTE 4: Contagem de parcelas até cada vencimento (1 scan)
contagem_parcelas AS (
  SELECT
    b.id_cliente,
    b.id_categoria,
    b.metodo_pagamento,
    SUM(CASE WHEN b.dt_venc <= v.primeiro_atraso THEN 1 ELSE 0 END) AS parcelas_ate_primeiro_atraso,
    SUM(CASE WHEN b.dt_venc <= v.proximo_vencimento THEN 1 ELSE 0 END) AS parcelas_ate_proximo_venc,
    SUM(CASE WHEN b.dt_venc <= v.ultimo_vencimento THEN 1 ELSE 0 END) AS parcelas_ate_ultimo_venc
  FROM base_data b
  INNER JOIN vencimentos_relevantes v
    ON b.id_cliente = v.id_cliente
    AND b.id_categoria = v.id_categoria
    AND b.metodo_pagamento = v.metodo_pagamento
  GROUP BY b.id_cliente, b.id_categoria, b.metodo_pagamento
)

-- SELECT FINAL: Apenas combina os resultados pré-calculados
SELECT
  a.id_cliente,
  a.nome_cliente,
  a.id_categoria,
  a.nome_categoria,
  a.metodo_pagamento,
  a.Compra,
  a.Aberto,
  a.Pago,
  a.Total,
  a.Pendentes,
  a.Pagas,
  a.Parcelas,
  a.Total_Parcelas_Contrato,
  a.Status,

  -- Parcela Atual (escolhe baseado no status)
  CASE
    WHEN a.max_fl_atrasada = 1 THEN c.parcelas_ate_primeiro_atraso
    WHEN a.max_fl_futura_em_aberto = 1 THEN c.parcelas_ate_proximo_venc
    ELSE c.parcelas_ate_ultimo_venc
  END AS Parcela_Atual,

  -- Vencimento Atual (escolhe baseado no status)
  CASE
    WHEN a.max_fl_atrasada = 1 THEN v.primeiro_atraso
    WHEN a.max_fl_futura_em_aberto = 1 THEN v.proximo_vencimento
    ELSE v.ultimo_vencimento
  END AS Vencimento_Atual

FROM agg_base a
INNER JOIN vencimentos_relevantes v
  ON a.id_cliente = v.id_cliente
  AND a.id_categoria = v.id_categoria
  AND a.metodo_pagamento = v.metodo_pagamento
INNER JOIN contagem_parcelas c
  ON a.id_cliente = c.id_cliente
  AND a.id_categoria = c.id_categoria
  AND a.metodo_pagamento = c.metodo_pagamento;
```

---

## Melhorias Implementadas

### 1. **CTEs (Common Table Expressions)**
- Divide a query em passos lógicos reutilizáveis
- Cada CTE processa a tabela apenas 1 vez
- MySQL pode otimizar melhor a execução

### 2. **Eliminação de Subconsultas Correlacionadas**
- **Antes**: 6-12 subconsultas por linha do resultado
- **Depois**: 0 subconsultas correlacionadas
- Cálculos feitos em CTEs com JOINs simples

### 3. **Redução de Scans da Tabela**
- **Antes**: 1 scan inicial + 6-12 scans por linha do resultado
- **Depois**: Aproximadamente 3-4 scans totais (base_data, vencimentos_relevantes, contagem_parcelas)

### 4. **Cálculos Únicos**
- Vencimentos relevantes calculados 1 vez por contrato
- Contagem de parcelas calculada 1 vez por contrato
- CASE no SELECT final apenas escolhe o valor pré-calculado

### 5. **Melhor Legibilidade**
- Cada CTE tem responsabilidade única
- Fácil de debugar cada etapa
- Comentários explicam a lógica

---

## Índices Recomendados

Para maximizar a performance, crie os seguintes índices:

```sql
-- Índice composto para agrupamento e JOINs
CREATE INDEX idx_contrato_grupo
ON dagiel67_central_mdzd.ContaAzulReceitas(
  id_cliente,
  id_categoria,
  metodo_pagamento
);

-- Índice para filtros de data e status
CREATE INDEX idx_vencimento_status
ON dagiel67_central_mdzd.ContaAzulReceitas(
  vencimento,
  status_traduzido,
  nao_pago
);

-- Índice covering para campos mais usados
CREATE INDEX idx_covering
ON dagiel67_central_mdzd.ContaAzulReceitas(
  id_cliente,
  id_categoria,
  metodo_pagamento,
  vencimento,
  status_traduzido,
  nao_pago,
  pago,
  rateio_valor
);
```

---

## Ganho de Performance Estimado

**Cenário**: 100.000 registros na tabela, 1.000 contratos únicos

| Métrica | Query Original | Query Otimizada | Melhoria |
|---------|---------------|-----------------|----------|
| **Scans da tabela** | ~12.000 | ~4 | **99,97%** |
| **Tempo estimado** | 30-120 segundos | 1-3 segundos | **90-95%** |
| **Uso de CPU** | Muito alto | Baixo | **~80%** |
| **Uso de memória** | Alto (subconsultas) | Moderado (CTEs) | **~40%** |

---

## Como Validar os Resultados

Para garantir que a query otimizada retorna os mesmos dados:

```sql
-- Execute ambas as queries e compare
CREATE TEMPORARY TABLE resultado_original AS
(... query original ...);

CREATE TEMPORARY TABLE resultado_otimizado AS
(... query otimizada ...);

-- Compare as diferenças
SELECT 'Original' AS fonte, COUNT(*) AS total FROM resultado_original
UNION ALL
SELECT 'Otimizado', COUNT(*) FROM resultado_otimizado;

-- Verifica registros diferentes
SELECT o.*
FROM resultado_original o
LEFT JOIN resultado_otimizado n USING (id_cliente, id_categoria, metodo_pagamento)
WHERE n.id_cliente IS NULL
   OR o.Parcela_Atual <> n.Parcela_Atual
   OR o.Vencimento_Atual <> n.Vencimento_Atual;
```

---

## Próximos Passos

1. **Teste em ambiente de desenvolvimento** primeiro
2. **Execute EXPLAIN** na query otimizada para verificar o plano de execução
3. **Crie os índices** recomendados
4. **Compare os resultados** com a query original
5. **Meça o tempo** de execução antes e depois
6. **Monitore** o uso de recursos no servidor

---

## Observações Adicionais

- **Compatibilidade**: A query otimizada usa CTEs (WITH), disponível no MySQL 8.0+
- **Materialização**: O MySQL pode materializar CTEs; teste o parâmetro `optimizer_switch` se necessário
- **Manutenção**: A query otimizada é mais fácil de manter e estender
- **Debug**: Para debugar, você pode executar cada CTE individualmente

Se tiver dúvidas ou precisar de ajustes, é só avisar!
