-- ============================================================
-- QUERY DEFINITIVA - OTIMIZADA PARA 29K REGISTROS
-- ============================================================
-- Baseada nos dados reais:
-- - 29.431 registros na tabela
-- - 5.560 contratos únicos no resultado
-- - Índices já criados e funcionando
--
-- Esta versão deve executar em 3-8 segundos
-- ============================================================

-- PASSO 1: Configurar sessão para performance máxima
SET SESSION tmp_table_size = 256*1024*1024;        -- 256MB (29k registros cabem fácil)
SET SESSION max_heap_table_size = 256*1024*1024;
SET SESSION sort_buffer_size = 32*1024*1024;
SET SESSION join_buffer_size = 16*1024*1024;

-- PASSO 2: Criar tabela temporária com dados pré-calculados (1 SCAN!)
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

-- PASSO 3: Criar índice composto otimizado
ALTER TABLE temp_base
ADD INDEX idx_fast (id_cliente, id_categoria, metodo_pagamento, dt_venc, fl_atrasada, fl_futura);

-- PASSO 4: Query final simplificada e otimizada
SELECT
  base.id_cliente,
  base.nome_cliente,
  base.id_categoria,
  base.nome_categoria,
  base.metodo_pagamento,
  base.Compra,
  base.Aberto,
  base.Pago,
  base.Total,
  base.Pendentes,
  base.Pagas,
  base.Parcelas,
  base.Total_Parcelas_Contrato,
  base.Status,

  -- Parcela Atual
  CASE base.Status
    WHEN 'Atraso' THEN base.parcelas_ate_atraso
    WHEN 'Ativo' THEN base.parcelas_ate_futuro
    ELSE base.Parcelas
  END AS Parcela_Atual,

  -- Vencimento Atual
  CASE base.Status
    WHEN 'Atraso' THEN base.dt_atraso
    WHEN 'Ativo' THEN base.dt_futuro
    ELSE base.dt_ultimo
  END AS Vencimento_Atual

FROM (
  SELECT
    t1.id_cliente,
    MAX(t1.nome_cliente) AS nome_cliente,
    t1.id_categoria,
    MAX(t1.nome_categoria) AS nome_categoria,
    t1.metodo_pagamento,

    -- Agregações básicas
    MIN(t1.data_compra) AS Compra,
    SUM(t1.vl_nao_pago) AS Aberto,
    SUM(t1.vl_pago) AS Pago,
    SUM(t1.vl_total) AS Total,
    SUM(t1.fl_pendente) AS Pendentes,
    SUM(t1.fl_paga) AS Pagas,
    COUNT(*) AS Parcelas,
    COALESCE(NULLIF(MAX(t1.qtd_parcelas_contrato), 0), COUNT(*)) AS Total_Parcelas_Contrato,

    -- Status
    CASE
      WHEN MAX(t1.fl_atrasada) = 1 THEN 'Atraso'
      WHEN MAX(t1.fl_futura) = 1 THEN 'Ativo'
      ELSE 'Quitado'
    END AS Status,

    -- Vencimentos (tudo em uma única passagem!)
    MIN(CASE WHEN t1.fl_atrasada = 1 THEN t1.dt_venc END) AS dt_atraso,
    MIN(CASE WHEN t1.fl_futura = 1 THEN t1.dt_venc END) AS dt_futuro,
    MAX(t1.dt_venc) AS dt_ultimo,

    -- Contagem de parcelas (subconsulta correlacionada otimizada)
    (SELECT COUNT(*)
     FROM temp_base t2
     WHERE t2.id_cliente = t1.id_cliente
       AND t2.id_categoria = t1.id_categoria
       AND t2.metodo_pagamento = t1.metodo_pagamento
       AND t2.dt_venc <= (
         SELECT MIN(t3.dt_venc)
         FROM temp_base t3
         WHERE t3.id_cliente = t1.id_cliente
           AND t3.id_categoria = t1.id_categoria
           AND t3.metodo_pagamento = t1.metodo_pagamento
           AND t3.fl_atrasada = 1
       )
    ) AS parcelas_ate_atraso,

    (SELECT COUNT(*)
     FROM temp_base t2
     WHERE t2.id_cliente = t1.id_cliente
       AND t2.id_categoria = t1.id_categoria
       AND t2.metodo_pagamento = t1.metodo_pagamento
       AND t2.dt_venc <= (
         SELECT MIN(t3.dt_venc)
         FROM temp_base t3
         WHERE t3.id_cliente = t1.id_cliente
           AND t3.id_categoria = t1.id_categoria
           AND t3.metodo_pagamento = t1.metodo_pagamento
           AND t3.fl_futura = 1
       )
    ) AS parcelas_ate_futuro

  FROM temp_base t1
  GROUP BY t1.id_cliente, t1.id_categoria, t1.metodo_pagamento
) base;

-- PASSO 5: Limpar
DROP TEMPORARY TABLE IF EXISTS temp_base;


-- ============================================================
-- NOTAS:
-- ============================================================
-- 1. Esta query usa tabela temporária em MEMÓRIA (super rápida)
-- 2. Com 29k registros, cabe tranquilamente na memória
-- 3. O índice composto otimiza as subconsultas correlacionadas
-- 4. Tempo esperado: 3-8 segundos (vs 70s original)
--
-- Se ainda estiver lento, use a versão COM PAGINAÇÃO abaixo
