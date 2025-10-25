-- ============================================================
-- QUERY OTIMIZADA - MELHOR VERSÃO para MySQL 5.7
-- ============================================================
-- Esta versão minimiza a repetição de subqueries e é mais eficiente
-- que a versão anterior, mesmo sem CTEs
-- ============================================================

SELECT
  agg.id_cliente,
  agg.nome_cliente,
  agg.id_categoria,
  agg.nome_categoria,
  agg.metodo_pagamento,
  agg.Compra,
  agg.Aberto,
  agg.Pago,
  agg.Total,
  agg.Pendentes,
  agg.Pagas,
  agg.Parcelas,
  agg.Total_Parcelas_Contrato,
  agg.Status,

  -- Parcela Atual
  CASE
    WHEN agg.max_fl_atrasada = 1 THEN agg.parcelas_ate_primeiro_atraso
    WHEN agg.max_fl_futura_em_aberto = 1 THEN agg.parcelas_ate_proximo_venc
    ELSE agg.parcelas_ate_ultimo_venc
  END AS Parcela_Atual,

  -- Vencimento Atual
  CASE
    WHEN agg.max_fl_atrasada = 1 THEN agg.primeiro_atraso
    WHEN agg.max_fl_futura_em_aberto = 1 THEN agg.proximo_vencimento
    ELSE agg.ultimo_vencimento
  END AS Vencimento_Atual

FROM (
  -- Todos os cálculos agrupados em uma única passagem
  SELECT
    base.id_cliente,
    MAX(base.nome_cliente) AS nome_cliente,
    base.id_categoria,
    MAX(base.nome_categoria) AS nome_categoria,
    base.metodo_pagamento,

    -- Agregações básicas
    MIN(base.data_compra) AS Compra,
    SUM(base.vl_nao_pago) AS Aberto,
    SUM(base.vl_pago) AS Pago,
    SUM(base.vl_total) AS Total,
    SUM(base.fl_pendente) AS Pendentes,
    SUM(base.fl_paga) AS Pagas,
    COUNT(*) AS Parcelas,
    COALESCE(MAX(base.qtd_parcelas_contrato), COUNT(*)) AS Total_Parcelas_Contrato,

    -- Flags de status
    MAX(base.fl_atrasada) AS max_fl_atrasada,
    MAX(base.fl_futura_em_aberto) AS max_fl_futura_em_aberto,

    -- Status
    CASE
      WHEN MAX(base.fl_atrasada) = 1 THEN 'Atraso'
      WHEN MAX(base.fl_futura_em_aberto) = 1 THEN 'Ativo'
      ELSE 'Quitado'
    END AS Status,

    -- Vencimentos relevantes
    MIN(CASE WHEN base.fl_atrasada = 1 THEN base.dt_venc END) AS primeiro_atraso,
    MIN(CASE WHEN base.fl_futura_em_aberto = 1 THEN base.dt_venc END) AS proximo_vencimento,
    MAX(base.dt_venc) AS ultimo_vencimento,

    -- Contagem de parcelas (calculado junto)
    SUM(CASE WHEN base.dt_venc <= (
      SELECT MIN(b2.dt_venc)
      FROM (
        SELECT
          id_cliente,
          id_categoria,
          metodo_pagamento,
          DATE(vencimento) AS dt_venc,
          CASE WHEN COALESCE(nao_pago, 0) > 0 AND DATE(vencimento) < CURDATE() THEN 1 ELSE 0 END AS fl_atrasada
        FROM dagiel67_central_mdzd.ContaAzulReceitas
      ) b2
      WHERE b2.id_cliente = base.id_cliente
        AND b2.id_categoria = base.id_categoria
        AND b2.metodo_pagamento = base.metodo_pagamento
        AND b2.fl_atrasada = 1
    ) THEN 1 ELSE 0 END) AS parcelas_ate_primeiro_atraso,

    SUM(CASE WHEN base.dt_venc <= (
      SELECT MIN(b2.dt_venc)
      FROM (
        SELECT
          id_cliente,
          id_categoria,
          metodo_pagamento,
          DATE(vencimento) AS dt_venc,
          CASE WHEN COALESCE(nao_pago, 0) > 0 AND DATE(vencimento) >= CURDATE() THEN 1 ELSE 0 END AS fl_futura
        FROM dagiel67_central_mdzd.ContaAzulReceitas
      ) b2
      WHERE b2.id_cliente = base.id_cliente
        AND b2.id_categoria = base.id_categoria
        AND b2.metodo_pagamento = base.metodo_pagamento
        AND b2.fl_futura = 1
    ) THEN 1 ELSE 0 END) AS parcelas_ate_proximo_venc,

    COUNT(*) AS parcelas_ate_ultimo_venc

  FROM (
    -- Dados base normalizados
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
  ) AS base

  GROUP BY base.id_cliente, base.id_categoria, base.metodo_pagamento
) AS agg;
