-- ============================================================
-- QUERY MAIS RÁPIDA POSSÍVEL - SEM SUBCONSULTAS CORRELACIONADAS
-- ============================================================
-- Para 29.431 registros → 5.560 contratos
-- Tempo esperado: 2-5 segundos
-- ============================================================

-- CONFIGURAÇÃO
SET SESSION tmp_table_size = 256*1024*1024;
SET SESSION max_heap_table_size = 256*1024*1024;

-- PASSO 1: Tabela temporária base (1 scan da tabela original)
DROP TEMPORARY TABLE IF EXISTS temp_base;
CREATE TEMPORARY TABLE temp_base
ENGINE=MEMORY
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
  quantidade_parcelas AS qtd_parcelas_contrato,
  CASE WHEN status_traduzido = 'RECEBIDO' THEN 1 ELSE 0 END AS fl_paga,
  CASE WHEN status_traduzido <> 'RECEBIDO' AND COALESCE(nao_pago, 0) > 0 THEN 1 ELSE 0 END AS fl_pendente,
  CASE WHEN COALESCE(nao_pago, 0) > 0 AND DATE(vencimento) < CURDATE() THEN 1 ELSE 0 END AS fl_atrasada,
  CASE WHEN COALESCE(nao_pago, 0) > 0 AND DATE(vencimento) >= CURDATE() THEN 1 ELSE 0 END AS fl_futura
FROM dagiel67_central_mdzd.ContaAzulReceitas;

-- Índice
ALTER TABLE temp_base
ADD INDEX idx_main (id_cliente, id_categoria, metodo_pagamento);

-- PASSO 2: Agregações e vencimentos (1 scan da temp_base)
DROP TEMPORARY TABLE IF EXISTS temp_agregado;
CREATE TEMPORARY TABLE temp_agregado
ENGINE=MEMORY
SELECT
  id_cliente,
  MAX(nome_cliente) AS nome_cliente,
  id_categoria,
  MAX(nome_categoria) AS nome_categoria,
  metodo_pagamento,
  MIN(data_compra) AS Compra,
  SUM(vl_nao_pago) AS Aberto,
  SUM(vl_pago) AS Pago,
  SUM(vl_total) AS Total,
  SUM(fl_pendente) AS Pendentes,
  SUM(fl_paga) AS Pagas,
  COUNT(*) AS Parcelas,
  COALESCE(NULLIF(MAX(qtd_parcelas_contrato), 0), COUNT(*)) AS Total_Parcelas_Contrato,
  MAX(fl_atrasada) AS tem_atraso,
  MAX(fl_futura) AS tem_futuro,
  CASE
    WHEN MAX(fl_atrasada) = 1 THEN 'Atraso'
    WHEN MAX(fl_futura) = 1 THEN 'Ativo'
    ELSE 'Quitado'
  END AS Status,
  MIN(CASE WHEN fl_atrasada = 1 THEN dt_venc END) AS dt_atraso,
  MIN(CASE WHEN fl_futura = 1 THEN dt_venc END) AS dt_futuro,
  MAX(dt_venc) AS dt_ultimo
FROM temp_base
GROUP BY id_cliente, id_categoria, metodo_pagamento;

-- Índice
ALTER TABLE temp_agregado
ADD INDEX idx_agg (id_cliente, id_categoria, metodo_pagamento);

-- PASSO 3: Contagem de parcelas até atraso (otimizado)
DROP TEMPORARY TABLE IF EXISTS temp_count_atraso;
CREATE TEMPORARY TABLE temp_count_atraso
ENGINE=MEMORY
SELECT
  b.id_cliente,
  b.id_categoria,
  b.metodo_pagamento,
  COUNT(*) AS parcelas_ate_atraso
FROM temp_base b
INNER JOIN temp_agregado a
  ON b.id_cliente = a.id_cliente
  AND b.id_categoria = a.id_categoria
  AND b.metodo_pagamento = a.metodo_pagamento
WHERE b.dt_venc <= a.dt_atraso
GROUP BY b.id_cliente, b.id_categoria, b.metodo_pagamento;

-- Índice
ALTER TABLE temp_count_atraso
ADD INDEX idx_ca (id_cliente, id_categoria, metodo_pagamento);

-- PASSO 4: Contagem de parcelas até futuro (otimizado)
DROP TEMPORARY TABLE IF EXISTS temp_count_futuro;
CREATE TEMPORARY TABLE temp_count_futuro
ENGINE=MEMORY
SELECT
  b.id_cliente,
  b.id_categoria,
  b.metodo_pagamento,
  COUNT(*) AS parcelas_ate_futuro
FROM temp_base b
INNER JOIN temp_agregado a
  ON b.id_cliente = a.id_cliente
  AND b.id_categoria = a.id_categoria
  AND b.metodo_pagamento = a.metodo_pagamento
WHERE b.dt_venc <= a.dt_futuro
GROUP BY b.id_cliente, b.id_categoria, b.metodo_pagamento;

-- Índice
ALTER TABLE temp_count_futuro
ADD INDEX idx_cf (id_cliente, id_categoria, metodo_pagamento);

-- PASSO 5: QUERY FINAL - Apenas JOINs, zero subconsultas!
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

  -- Parcela Atual
  CASE
    WHEN a.tem_atraso = 1 THEN IFNULL(ca.parcelas_ate_atraso, a.Parcelas)
    WHEN a.tem_futuro = 1 THEN IFNULL(cf.parcelas_ate_futuro, a.Parcelas)
    ELSE a.Parcelas
  END AS Parcela_Atual,

  -- Vencimento Atual
  CASE
    WHEN a.tem_atraso = 1 THEN a.dt_atraso
    WHEN a.tem_futuro = 1 THEN a.dt_futuro
    ELSE a.dt_ultimo
  END AS Vencimento_Atual

FROM temp_agregado a
LEFT JOIN temp_count_atraso ca
  ON a.id_cliente = ca.id_cliente
  AND a.id_categoria = ca.id_categoria
  AND a.metodo_pagamento = ca.metodo_pagamento
LEFT JOIN temp_count_futuro cf
  ON a.id_cliente = cf.id_cliente
  AND a.id_categoria = cf.id_categoria
  AND a.metodo_pagamento = cf.metodo_pagamento;

-- PASSO 6: Limpar
DROP TEMPORARY TABLE IF EXISTS temp_base;
DROP TEMPORARY TABLE IF EXISTS temp_agregado;
DROP TEMPORARY TABLE IF EXISTS temp_count_atraso;
DROP TEMPORARY TABLE IF EXISTS temp_count_futuro;


-- ============================================================
-- RESULTADO ESPERADO:
-- ============================================================
-- Tempo: 2-5 segundos para consulta
-- Rows: 5.560 contratos
--
-- Esta é a versão MAIS RÁPIDA possível porque:
-- 1. Apenas 1 scan da tabela original
-- 2. Zero subconsultas correlacionadas
-- 3. Tudo em memória (MEMORY engine)
-- 4. Índices otimizados em cada temp table
-- 5. Query final é apenas 2 LEFT JOINs simples
-- ============================================================
