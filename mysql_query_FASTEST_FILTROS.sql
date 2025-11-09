-- ============================================================
-- STORED PROCEDURE: afs_receitas_consolidadas_filtrada
-- ============================================================
-- Versão COM FILTROS de Status + COLUNA COBRANCA
-- ============================================================

DROP PROCEDURE IF EXISTS dagiel67_central_mdzd.afs_receitas_consolidadas_filtrada;

DELIMITER $$

CREATE DEFINER=`dagiel67_central_mdzd1`@`%` PROCEDURE `afs_receitas_consolidadas_filtrada`(
  IN p_filtro_status VARCHAR(500)  -- Valores: NULL (todos), 'Atraso', 'Aberto', 'Ativo', 'Quitado' ou combinações: 'Atraso,Aberto'
)
BEGIN

-- Variáveis para os filtros
DECLARE v_filtrar_atraso BOOLEAN DEFAULT FALSE;
DECLARE v_filtrar_aberto BOOLEAN DEFAULT FALSE;
DECLARE v_filtrar_ativo BOOLEAN DEFAULT FALSE;
DECLARE v_filtrar_quitado BOOLEAN DEFAULT FALSE;
DECLARE v_usar_filtro BOOLEAN DEFAULT FALSE;

-- CONFIGURAÇÃO
SET SESSION tmp_table_size = 256*1024*1024;
SET SESSION max_heap_table_size = 256*1024*1024;

-- Processar o parâmetro de filtro
IF p_filtro_status IS NOT NULL AND p_filtro_status <> '' THEN
  SET v_usar_filtro = TRUE;
  SET v_filtrar_atraso = (FIND_IN_SET('Atraso', p_filtro_status) > 0);
  SET v_filtrar_aberto = (FIND_IN_SET('Aberto', p_filtro_status) > 0);
  SET v_filtrar_ativo = (FIND_IN_SET('Ativo', p_filtro_status) > 0);
  SET v_filtrar_quitado = (FIND_IN_SET('Quitado', p_filtro_status) > 0);
END IF;

-- PASSO 1: Tabela temporária base (1 scan da tabela original)
DROP TEMPORARY TABLE IF EXISTS temp_base;
CREATE TEMPORARY TABLE temp_base
ENGINE=MEMORY
SELECT
  dagiel67_central_mdzd.ContaAzulReceitas.id_cliente,
  dagiel67_central_mdzd.ContaAzulReceitas.nome_cliente,
  dagiel67_central_mdzd.ContaAzulPessoas.email,
  dagiel67_central_mdzd.ContaAzulPessoas.documento,
  dagiel67_central_mdzd.ContaAzulPessoas.telefone,
  dagiel67_central_mdzd.ContaAzulReceitas.id_categoria,
  dagiel67_central_mdzd.ContaAzulReceitas.nome_categoria,
  dagiel67_central_mdzd.ContaAzulReceitas.metodo_pagamento,
  DATE(dagiel67_central_mdzd.ContaAzulReceitas.data_criacao) AS data_compra,
  DATE(dagiel67_central_mdzd.ContaAzulReceitas.vencimento) AS dt_venc,
  COALESCE(dagiel67_central_mdzd.ContaAzulReceitas.nao_pago, 0) AS vl_nao_pago,
  COALESCE(dagiel67_central_mdzd.ContaAzulReceitas.pago, 0) AS vl_pago,
  COALESCE(dagiel67_central_mdzd.ContaAzulReceitas.bruto, 0) AS vl_total,
  1 AS qtd_parcelas_contrato,
  CASE WHEN dagiel67_central_mdzd.ContaAzulReceitas.status_traduzido = 'RECEBIDO' THEN 1 ELSE 0 END AS fl_paga,
  CASE WHEN dagiel67_central_mdzd.ContaAzulReceitas.status_traduzido <> 'RECEBIDO' THEN 1 ELSE 0 END AS fl_pendente,
  CASE WHEN dagiel67_central_mdzd.ContaAzulReceitas.status_traduzido <> 'RECEBIDO' AND DATE(dagiel67_central_mdzd.ContaAzulReceitas.vencimento) < CURDATE() THEN 1 ELSE 0 END AS fl_atrasada,
  CASE WHEN dagiel67_central_mdzd.ContaAzulReceitas.status_traduzido <> 'RECEBIDO' AND DATE(dagiel67_central_mdzd.ContaAzulReceitas.vencimento) >= CURDATE() THEN 1 ELSE 0 END AS fl_futura
FROM dagiel67_central_mdzd.ContaAzulReceitas
LEFT JOIN dagiel67_central_mdzd.ContaAzulPessoas ON dagiel67_central_mdzd.ContaAzulReceitas.id_cliente = dagiel67_central_mdzd.ContaAzulPessoas.id
WHERE (dagiel67_central_mdzd.ContaAzulReceitas.status_traduzido <> 'RENEGOCIADO' AND dagiel67_central_mdzd.ContaAzulReceitas.status_traduzido <> 'EXCLUIR');

-- Índice
ALTER TABLE temp_base
ADD INDEX idx_main (id_cliente, id_categoria);

-- PASSO 2: Agregações e vencimentos (1 scan da temp_base)
DROP TEMPORARY TABLE IF EXISTS temp_agregado;
CREATE TEMPORARY TABLE temp_agregado
ENGINE=MEMORY
SELECT
  id_cliente,
  MAX(nome_cliente) AS nome_cliente,
  MAX(email) AS email,
  MAX(documento) AS documento,
  id_categoria,
  MAX(nome_categoria) AS nome_categoria,
  MAX(metodo_pagamento) AS metodo_pagamento,
  MAX(telefone) AS telefone,
  MIN(data_compra) AS Compra,
  SUM(vl_nao_pago) AS Aberto,
  SUM(vl_pago) AS Pago,
  SUM(vl_total) AS Total,
  SUM(fl_pendente) AS Pendentes,
  SUM(fl_paga) AS Pagas,
  COUNT(qtd_parcelas_contrato) AS Parcelas,
  MAX(fl_atrasada) AS tem_atraso,
  MAX(fl_futura) AS tem_futuro,
  CASE
    WHEN MAX(fl_atrasada) = 1 THEN 'Atraso'
    WHEN MAX(fl_futura) = 1 AND SUM(vl_pago) > 0 THEN 'Ativo'
    WHEN MAX(fl_futura) = 1 AND MAX(fl_atrasada) = 0 AND SUM(vl_pago) = 0 THEN 'Aberto'
    WHEN MAX(fl_futura) = 1 AND MAX(fl_atrasada) = 1 AND SUM(vl_pago) = 0 THEN 'Atraso'
    ELSE 'Quitado'
  END AS Status,
  MIN(CASE WHEN fl_atrasada = 1 THEN dt_venc END) AS dt_atraso,
  MIN(CASE WHEN fl_futura = 1 THEN dt_venc END) AS dt_futuro,
  MAX(dt_venc) AS dt_ultimo,
  -- NOVA COLUNA: Primeira parcela pendente (para Cobrança)
  MIN(CASE WHEN fl_pendente = 1 THEN dt_venc END) AS dt_primeira_pendente
FROM temp_base
GROUP BY id_cliente, id_categoria;

-- Índice
ALTER TABLE temp_agregado
ADD INDEX idx_agg (id_cliente, id_categoria),
ADD INDEX idx_status (Status);

-- PASSO 3: Contagem de parcelas até atraso (otimizado)
DROP TEMPORARY TABLE IF EXISTS temp_count_atraso;
CREATE TEMPORARY TABLE temp_count_atraso
ENGINE=MEMORY
SELECT
  b.id_cliente,
  b.id_categoria,
  MAX(b.metodo_pagamento) AS metodo_pagamento,
  COUNT(*) AS parcelas_ate_atraso
FROM temp_base b
INNER JOIN temp_agregado a
  ON b.id_cliente = a.id_cliente
  AND b.id_categoria = a.id_categoria
WHERE b.dt_venc <= a.dt_atraso
GROUP BY b.id_cliente, b.id_categoria;

-- Índice
ALTER TABLE temp_count_atraso
ADD INDEX idx_ca (id_cliente, id_categoria);

-- PASSO 4: Contagem de parcelas até futuro (otimizado)
DROP TEMPORARY TABLE IF EXISTS temp_count_futuro;
CREATE TEMPORARY TABLE temp_count_futuro
ENGINE=MEMORY
SELECT
  b.id_cliente,
  b.id_categoria,
  MAX(b.metodo_pagamento) AS metodo_pagamento,
  COUNT(*) AS parcelas_ate_futuro
FROM temp_base b
INNER JOIN temp_agregado a
  ON b.id_cliente = a.id_cliente
  AND b.id_categoria = a.id_categoria
WHERE b.dt_venc <= a.dt_futuro
GROUP BY b.id_cliente, b.id_categoria;

-- Índice
ALTER TABLE temp_count_futuro
ADD INDEX idx_cf (id_cliente, id_categoria);

-- PASSO 5: QUERY FINAL COM FILTRO DE STATUS + COLUNA COBRANCA
SELECT
  a.id_cliente,
  a.nome_cliente,
  a.email,
  a.documento,
  a.telefone,
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
  a.Status,

  -- Parcela Atual
  CASE
    WHEN a.tem_atraso = 1 AND a.tem_futuro = 0 THEN IFNULL(ca.parcelas_ate_atraso, a.Parcelas)
    WHEN a.tem_atraso = 1 AND a.tem_futuro = 1 THEN IFNULL(cf.parcelas_ate_futuro, a.Parcelas)
    WHEN a.tem_futuro = 1 AND a.tem_atraso = 0 THEN IFNULL(cf.parcelas_ate_futuro, a.Parcelas)
    ELSE a.Parcelas
  END AS Parcela_Atual,

  -- Vencimento Atual
  CASE
    WHEN a.tem_atraso = 1 AND a.tem_futuro = 1 THEN a.dt_futuro
    WHEN a.tem_atraso = 1 AND a.tem_futuro = 0 THEN a.dt_atraso
    WHEN a.tem_futuro = 1 AND a.tem_atraso = 0 THEN a.dt_futuro
    ELSE a.dt_ultimo
  END AS Vencimento_Atual,

  -- NOVA COLUNA: Cobranca
  -- Para Atraso, Aberto, Ativo: primeira parcela pendente
  -- Para Quitado: última parcela
  CASE
    WHEN a.Status IN ('Atraso', 'Aberto', 'Ativo') THEN a.dt_primeira_pendente
    ELSE a.dt_ultimo
  END AS Cobranca

FROM temp_agregado a
LEFT JOIN temp_count_atraso ca
  ON a.id_cliente = ca.id_cliente
  AND a.id_categoria = ca.id_categoria
LEFT JOIN temp_count_futuro cf
  ON a.id_cliente = cf.id_cliente
  AND a.id_categoria = cf.id_categoria
WHERE a.id_cliente IS NOT NULL
  -- APLICAR FILTRO DE STATUS
  AND (
    -- Se não usar filtro, retorna tudo
    v_usar_filtro = FALSE
    OR
    -- Se usar filtro, verifica cada status
    (
      (v_filtrar_atraso = TRUE AND a.Status = 'Atraso')
      OR
      (v_filtrar_aberto = TRUE AND a.Status = 'Aberto')
      OR
      (v_filtrar_ativo = TRUE AND a.Status = 'Ativo')
      OR
      (v_filtrar_quitado = TRUE AND a.Status = 'Quitado')
    )
  );

-- PASSO 6: Limpar
DROP TEMPORARY TABLE IF EXISTS temp_base;
DROP TEMPORARY TABLE IF EXISTS temp_agregado;
DROP TEMPORARY TABLE IF EXISTS temp_count_atraso;
DROP TEMPORARY TABLE IF EXISTS temp_count_futuro;

END$$

DELIMITER ;


-- ============================================================
-- COMO USAR:
-- ============================================================
-- 1. Execute TODO o código acima para criar/atualizar a procedure
--
-- 2. Teste:
--    CALL dagiel67_central_mdzd.afs_receitas_consolidadas_filtrada(NULL);
--
-- ============================================================
-- NOVA COLUNA: Cobranca
-- ============================================================
-- A coluna Cobranca mostra:
-- - Atraso: Data da primeira parcela vencida pendente
-- - Aberto: Data da primeira parcela pendente (pode estar próxima)
-- - Ativo: Data da próxima parcela pendente
-- - Quitado: Data da última parcela (para referência)
--
-- Essa é a data que deve ser usada para cobrança/follow-up!
-- ============================================================
