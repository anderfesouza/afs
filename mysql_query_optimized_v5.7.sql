-- ========================================================
-- QUERY OTIMIZADA - MySQL 5.7 e anteriores (SEM CTEs)
-- ========================================================

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

FROM (
  -- Agregações principais
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
  FROM (
    -- Normalização dos dados base
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
  ) AS base_data
  GROUP BY id_cliente, nome_cliente, id_categoria, nome_categoria, metodo_pagamento
) AS a

INNER JOIN (
  -- Vencimentos relevantes
  SELECT
    id_cliente,
    id_categoria,
    metodo_pagamento,
    MIN(CASE WHEN fl_atrasada = 1 THEN dt_venc END) AS primeiro_atraso,
    MIN(CASE WHEN fl_futura_em_aberto = 1 THEN dt_venc END) AS proximo_vencimento,
    MAX(dt_venc) AS ultimo_vencimento
  FROM (
    SELECT
      id_cliente,
      id_categoria,
      metodo_pagamento,
      DATE(vencimento) AS dt_venc,
      CASE WHEN COALESCE(nao_pago, 0) > 0 AND DATE(vencimento) < CURDATE() THEN 1 ELSE 0 END AS fl_atrasada,
      CASE WHEN COALESCE(nao_pago, 0) > 0 AND DATE(vencimento) >= CURDATE() THEN 1 ELSE 0 END AS fl_futura_em_aberto
    FROM dagiel67_central_mdzd.ContaAzulReceitas
  ) AS base_venc
  GROUP BY id_cliente, id_categoria, metodo_pagamento
) AS v
  ON a.id_cliente = v.id_cliente
  AND a.id_categoria = v.id_categoria
  AND a.metodo_pagamento = v.metodo_pagamento

INNER JOIN (
  -- Contagem de parcelas
  SELECT
    b.id_cliente,
    b.id_categoria,
    b.metodo_pagamento,
    SUM(CASE WHEN b.dt_venc <= v.primeiro_atraso THEN 1 ELSE 0 END) AS parcelas_ate_primeiro_atraso,
    SUM(CASE WHEN b.dt_venc <= v.proximo_vencimento THEN 1 ELSE 0 END) AS parcelas_ate_proximo_venc,
    SUM(CASE WHEN b.dt_venc <= v.ultimo_vencimento THEN 1 ELSE 0 END) AS parcelas_ate_ultimo_venc
  FROM (
    SELECT
      id_cliente,
      id_categoria,
      metodo_pagamento,
      DATE(vencimento) AS dt_venc
    FROM dagiel67_central_mdzd.ContaAzulReceitas
  ) AS b
  INNER JOIN (
    SELECT
      id_cliente,
      id_categoria,
      metodo_pagamento,
      MIN(CASE WHEN fl_atrasada = 1 THEN dt_venc END) AS primeiro_atraso,
      MIN(CASE WHEN fl_futura_em_aberto = 1 THEN dt_venc END) AS proximo_vencimento,
      MAX(dt_venc) AS ultimo_vencimento
    FROM (
      SELECT
        id_cliente,
        id_categoria,
        metodo_pagamento,
        DATE(vencimento) AS dt_venc,
        CASE WHEN COALESCE(nao_pago, 0) > 0 AND DATE(vencimento) < CURDATE() THEN 1 ELSE 0 END AS fl_atrasada,
        CASE WHEN COALESCE(nao_pago, 0) > 0 AND DATE(vencimento) >= CURDATE() THEN 1 ELSE 0 END AS fl_futura_em_aberto
      FROM dagiel67_central_mdzd.ContaAzulReceitas
    ) AS base_venc2
    GROUP BY id_cliente, id_categoria, metodo_pagamento
  ) AS v
    ON b.id_cliente = v.id_cliente
    AND b.id_categoria = v.id_categoria
    AND b.metodo_pagamento = v.metodo_pagamento
  GROUP BY b.id_cliente, b.id_categoria, b.metodo_pagamento
) AS c
  ON a.id_cliente = c.id_cliente
  AND a.id_categoria = c.id_categoria
  AND a.metodo_pagamento = c.metodo_pagamento;
