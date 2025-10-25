-- ============================================================
-- QUERY ULTRA-OTIMIZADA - VERSÃO CORRIGIDA
-- ============================================================
-- Correção: Total_Parcelas_Contrato agora conta corretamente
-- Usa tabela temporária em memória para máxima velocidade
-- ============================================================

-- PASSO 1: Criar e popular tabela temporária (1 scan da tabela original!)
DROP TEMPORARY TABLE IF EXISTS temp_base_data;
CREATE TEMPORARY TABLE temp_base_data
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
  CASE WHEN COALESCE(nao_pago, 0) > 0 AND DATE(vencimento) >= CURDATE() THEN 1 ELSE 0 END AS fl_futura_em_aberto
FROM dagiel67_central_mdzd.ContaAzulReceitas;

-- PASSO 2: Criar índices
ALTER TABLE temp_base_data
ADD INDEX idx_contrato (id_cliente, id_categoria, metodo_pagamento),
ADD INDEX idx_venc (dt_venc);

-- PASSO 3: Query final
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
    WHEN a.max_fl_atrasada = 1 THEN c.parcelas_ate_primeiro_atraso
    WHEN a.max_fl_futura_em_aberto = 1 THEN c.parcelas_ate_proximo_venc
    ELSE a.Parcelas
  END AS Parcela_Atual,

  -- Vencimento Atual
  CASE
    WHEN a.max_fl_atrasada = 1 THEN v.primeiro_atraso
    WHEN a.max_fl_futura_em_aberto = 1 THEN v.proximo_vencimento
    ELSE v.ultimo_vencimento
  END AS Vencimento_Atual

FROM (
  -- Agregações principais
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
    -- CORRIGIDO: agora usa COUNT(qtd_parcelas_contrato) se existir, senão COUNT(*)
    COALESCE(
      NULLIF(MAX(qtd_parcelas_contrato), 0),
      COUNT(*)
    ) AS Total_Parcelas_Contrato,
    MAX(fl_atrasada) AS max_fl_atrasada,
    MAX(fl_futura_em_aberto) AS max_fl_futura_em_aberto,
    CASE
      WHEN MAX(fl_atrasada) = 1 THEN 'Atraso'
      WHEN MAX(fl_futura_em_aberto) = 1 THEN 'Ativo'
      ELSE 'Quitado'
    END AS Status
  FROM temp_base_data
  GROUP BY id_cliente, id_categoria, metodo_pagamento
) a

INNER JOIN (
  -- Vencimentos relevantes
  SELECT
    id_cliente,
    id_categoria,
    metodo_pagamento,
    MIN(CASE WHEN fl_atrasada = 1 THEN dt_venc END) AS primeiro_atraso,
    MIN(CASE WHEN fl_futura_em_aberto = 1 THEN dt_venc END) AS proximo_vencimento,
    MAX(dt_venc) AS ultimo_vencimento
  FROM temp_base_data
  GROUP BY id_cliente, id_categoria, metodo_pagamento
) v
  ON a.id_cliente = v.id_cliente
  AND a.id_categoria = v.id_categoria
  AND a.metodo_pagamento = v.metodo_pagamento

INNER JOIN (
  -- Contagem de parcelas
  SELECT
    b.id_cliente,
    b.id_categoria,
    b.metodo_pagamento,
    SUM(CASE WHEN b.dt_venc <= IFNULL(v.primeiro_atraso, '9999-12-31') THEN 1 ELSE 0 END) AS parcelas_ate_primeiro_atraso,
    SUM(CASE WHEN b.dt_venc <= IFNULL(v.proximo_vencimento, '9999-12-31') THEN 1 ELSE 0 END) AS parcelas_ate_proximo_venc
  FROM temp_base_data b
  LEFT JOIN (
    SELECT
      id_cliente,
      id_categoria,
      metodo_pagamento,
      MIN(CASE WHEN fl_atrasada = 1 THEN dt_venc END) AS primeiro_atraso,
      MIN(CASE WHEN fl_futura_em_aberto = 1 THEN dt_venc END) AS proximo_vencimento
    FROM temp_base_data
    GROUP BY id_cliente, id_categoria, metodo_pagamento
  ) v
    ON b.id_cliente = v.id_cliente
    AND b.id_categoria = v.id_categoria
    AND b.metodo_pagamento = v.metodo_pagamento
  GROUP BY b.id_cliente, b.id_categoria, b.metodo_pagamento
) c
  ON a.id_cliente = c.id_cliente
  AND a.id_categoria = c.id_categoria
  AND a.metodo_pagamento = c.metodo_pagamento;

-- PASSO 4: Limpar
DROP TEMPORARY TABLE IF EXISTS temp_base_data;


-- ============================================================
-- NOTAS DE USO:
-- ============================================================
-- 1. Esta query usa ENGINE=MEMORY (muito rápida)
-- 2. Se der erro de memória, use mysql_query_ULTRA_OPTIMIZED_v2.sql
-- 3. Para verificar limite de memória:
--    SHOW VARIABLES LIKE 'tmp_table_size';
--    SHOW VARIABLES LIKE 'max_heap_table_size';
-- 4. Para aumentar (se necessário):
--    SET SESSION tmp_table_size = 256*1024*1024;  -- 256MB
--    SET SESSION max_heap_table_size = 256*1024*1024;  -- 256MB
