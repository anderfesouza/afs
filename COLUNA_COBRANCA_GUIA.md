# 📅 Coluna Cobranca - Guia Completo

## O que é a coluna Cobranca?

A coluna **Cobranca** mostra a **data ideal para follow-up ou cobrança** de cada contrato, facilitando a gestão de cobranças e notificações automatizadas.

---

## 📊 Como Funciona por Status

| Status | Data Mostrada | Descrição | Exemplo de Uso |
|--------|---------------|-----------|----------------|
| **Atraso** | Primeira parcela vencida pendente | Data da parcela mais antiga em atraso | Enviar notificação urgente |
| **Aberto** | Primeira parcela pendente | Data da próxima parcela a vencer (pode estar próxima) | Lembrete de vencimento |
| **Ativo** | Próxima parcela pendente | Data da próxima parcela futura | Notificação preventiva |
| **Quitado** | Última parcela | Data da última parcela paga (referência) | Histórico do contrato |

---

## 🎯 Casos de Uso Práticos

### 1. Dashboard de Cobrança Ordenado por Prioridade

```sql
-- Contratos ordenados por urgência de cobrança
CALL dagiel67_central_mdzd.afs_receitas_consolidadas_filtrada('Atraso,Aberto,Ativo')
ORDER BY Cobranca ASC;
```

**Resultado**: Primeiro aparecem os contratos com parcelas mais antigas pendentes.

---

### 2. Notificações Automatizadas de Vencimento

```sql
-- Contratos que vencem hoje
CALL dagiel67_central_mdzd.afs_receitas_consolidadas_filtrada(NULL)
WHERE Cobranca = CURDATE()
  AND Status IN ('Aberto', 'Ativo');
```

**Uso**: Enviar email/SMS automático no dia do vencimento.

---

### 3. Alertas de Parcelas Atrasadas

```sql
-- Contratos em atraso há mais de 7 dias
CALL dagiel67_central_mdzd.afs_receitas_consolidadas_filtrada('Atraso')
WHERE Cobranca < DATE_SUB(CURDATE(), INTERVAL 7 DAY);
```

**Uso**: Escalar para equipe de cobrança.

---

### 4. Previsão de Vencimentos (Próximos 7 dias)

```sql
-- Contratos que vencem nos próximos 7 dias
CALL dagiel67_central_mdzd.afs_receitas_consolidadas_filtrada('Aberto,Ativo')
WHERE Cobranca BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL 7 DAY);
```

**Uso**: Enviar lembrete preventivo.

---

### 5. Relatório de Inadimplência por Período

```sql
-- Contratos em atraso agrupados por mês
SELECT
  DATE_FORMAT(Cobranca, '%Y-%m') AS Mes,
  COUNT(*) AS Contratos,
  SUM(Aberto) AS Valor_Total
FROM (
  CALL dagiel67_central_mdzd.afs_receitas_consolidadas_filtrada('Atraso')
) AS resultado
GROUP BY DATE_FORMAT(Cobranca, '%Y-%m')
ORDER BY Mes DESC;
```

**Uso**: Dashboard gerencial de inadimplência.

---

## 💡 Diferença: Cobranca vs Vencimento_Atual

### Vencimento_Atual
- Mostra a data da **próxima parcela** no fluxo do contrato
- Pode ser uma parcela futura mesmo se houver atrasos

### Cobranca
- Mostra a data da **primeira parcela PENDENTE**
- Sempre mostra a parcela mais urgente a cobrar
- Ideal para workflows de cobrança

### Exemplo:

**Contrato com:**
- Parcela 1: Vencimento 01/01/2025 - **VENCIDA** (não paga)
- Parcela 2: Vencimento 01/02/2025 - **VENCIDA** (não paga)
- Parcela 3: Vencimento 01/03/2025 - Futura (não paga)
- Parcela 4: Vencimento 01/04/2025 - Futura (não paga)

**Valores das colunas:**
- **Status**: `Atraso` (tem parcelas vencidas)
- **Vencimento_Atual**: `01/03/2025` (próxima parcela no fluxo)
- **Cobranca**: `01/01/2025` ⭐ (primeira parcela pendente - mais urgente!)

---

## 🔧 Integração com Sistemas de Cobrança

### Workflow Automatizado

```sql
-- ETAPA 1: Buscar contratos para cobrar hoje
SELECT
  id_cliente,
  nome_cliente,
  email,
  telefone,
  Cobranca,
  Aberto AS valor_pendente,
  Status
FROM (
  CALL dagiel67_central_mdzd.afs_receitas_consolidadas_filtrada('Atraso,Aberto')
) AS resultado
WHERE Cobranca <= CURDATE()
ORDER BY
  CASE Status
    WHEN 'Atraso' THEN 1
    WHEN 'Aberto' THEN 2
    ELSE 3
  END,
  Cobranca ASC;

-- ETAPA 2: Para cada linha, enviar notificação
-- (implementar no seu sistema)
```

---

### Sistema de Notificações por Período

| Período | Tipo de Notificação | Filtro SQL |
|---------|---------------------|------------|
| **7 dias antes** | Lembrete preventivo | `Cobranca = DATE_ADD(CURDATE(), INTERVAL 7 DAY)` |
| **3 dias antes** | Alerta de vencimento | `Cobranca = DATE_ADD(CURDATE(), INTERVAL 3 DAY)` |
| **Dia do vencimento** | Notificação de vencimento | `Cobranca = CURDATE()` |
| **1 dia após** | Primeiro aviso de atraso | `Cobranca = DATE_SUB(CURDATE(), INTERVAL 1 DAY)` |
| **7 dias após** | Segunda cobrança | `Cobranca = DATE_SUB(CURDATE(), INTERVAL 7 DAY)` |
| **30 dias após** | Negativação | `Cobranca < DATE_SUB(CURDATE(), INTERVAL 30 DAY)` |

---

## 📱 Exemplos de Código

### PHP - Enviar Email de Cobrança

```php
<?php
// Buscar contratos que vencem hoje
$stmt = $pdo->query("
    CALL afs_receitas_consolidadas_filtrada('Atraso,Aberto')
");

$contratos = $stmt->fetchAll(PDO::FETCH_ASSOC);

foreach ($contratos as $contrato) {
    // Apenas contratos que vencem hoje ou estão atrasados
    if (strtotime($contrato['Cobranca']) <= time()) {

        // Escolher template baseado no status
        if ($contrato['Status'] == 'Atraso') {
            $template = 'email_cobranca_atraso';
            $assunto = 'URGENTE: Parcela em atraso';
        } else {
            $template = 'email_vencimento';
            $assunto = 'Lembrete: Parcela vence hoje';
        }

        // Enviar email
        enviarEmail(
            $contrato['email'],
            $assunto,
            $template,
            [
                'nome' => $contrato['nome_cliente'],
                'data_vencimento' => $contrato['Cobranca'],
                'valor' => $contrato['Aberto'],
            ]
        );
    }
}
?>
```

---

### Python - Notificações WhatsApp

```python
from datetime import datetime, timedelta
import mysql.connector

# Conectar ao banco
conn = mysql.connector.connect(...)
cursor = conn.cursor(dictionary=True)

# Buscar contratos
cursor.callproc('afs_receitas_consolidadas_filtrada', ['Atraso,Aberto'])

for result in cursor.stored_results():
    contratos = result.fetchall()

for contrato in contratos:
    # Calcular dias de atraso
    data_cobranca = contrato['Cobranca']
    dias_atraso = (datetime.now().date() - data_cobranca).days

    if dias_atraso > 0:
        # Em atraso
        mensagem = f"""
        Olá {contrato['nome_cliente']},

        Identificamos uma parcela em atraso há {dias_atraso} dias.
        Valor: R$ {contrato['Aberto']:.2f}
        Vencimento: {data_cobranca.strftime('%d/%m/%Y')}

        Por favor, regularize sua situação.
        """
    elif dias_atraso == 0:
        # Vence hoje
        mensagem = f"""
        Olá {contrato['nome_cliente']},

        Lembrete: Sua parcela vence HOJE!
        Valor: R$ {contrato['Aberto']:.2f}
        """

    # Enviar WhatsApp
    enviar_whatsapp(contrato['telefone'], mensagem)
```

---

### Node.js - Dashboard de Cobrança

```javascript
const mysql = require('mysql2/promise');

async function getDashboardCobranca() {
  const connection = await mysql.createConnection({...});

  const [contratos] = await connection.query(`
    CALL afs_receitas_consolidadas_filtrada('Atraso,Aberto,Ativo')
  `);

  // Agrupar por urgência
  const dashboard = {
    urgente: [],      // Atrasados há mais de 7 dias
    atencao: [],      // Atrasados há menos de 7 dias
    proximoVencimento: [], // Vencem nos próximos 3 dias
    noVencimento: []  // Vencem hoje
  };

  const hoje = new Date();

  contratos[0].forEach(contrato => {
    const dataCobranca = new Date(contrato.Cobranca);
    const diasDif = Math.floor((hoje - dataCobranca) / (1000 * 60 * 60 * 24));

    if (diasDif > 7) {
      dashboard.urgente.push(contrato);
    } else if (diasDif > 0) {
      dashboard.atencao.push(contrato);
    } else if (diasDif === 0) {
      dashboard.noVencimento.push(contrato);
    } else if (diasDif >= -3) {
      dashboard.proximoVencimento.push(contrato);
    }
  });

  return dashboard;
}
```

---

## 🎨 Exibição no Frontend

### Cores por Status da Cobrança

```javascript
function getCorCobranca(dataCobranca, status) {
  const hoje = new Date();
  const cobranca = new Date(dataCobranca);
  const diasDif = Math.floor((hoje - cobranca) / (1000 * 60 * 60 * 24));

  if (status === 'Quitado') return 'green';
  if (diasDif > 30) return 'red';        // Vermelho: 30+ dias de atraso
  if (diasDif > 7) return 'orange';      // Laranja: 7-30 dias de atraso
  if (diasDif > 0) return 'yellow';      // Amarelo: 1-7 dias de atraso
  if (diasDif === 0) return 'blue';      // Azul: Vence hoje
  return 'gray';                          // Cinza: Vencimento futuro
}
```

---

## 📈 Métricas e KPIs

### Exemplos de Métricas Úteis

```sql
-- Taxa de inadimplência
SELECT
  COUNT(CASE WHEN Status = 'Atraso' THEN 1 END) * 100.0 / COUNT(*) AS taxa_inadimplencia
FROM (CALL afs_receitas_consolidadas_filtrada(NULL));

-- Valor médio em atraso por cliente
SELECT AVG(Aberto) AS media_atraso
FROM (CALL afs_receitas_consolidadas_filtrada('Atraso'));

-- Tempo médio de atraso
SELECT AVG(DATEDIFF(CURDATE(), Cobranca)) AS dias_medio_atraso
FROM (CALL afs_receitas_consolidadas_filtrada('Atraso'));

-- Distribuição de vencimentos (próximos 30 dias)
SELECT
  DATE(Cobranca) AS data,
  COUNT(*) AS contratos,
  SUM(Aberto) AS valor_total
FROM (CALL afs_receitas_consolidadas_filtrada('Aberto,Ativo'))
WHERE Cobranca BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL 30 DAY)
GROUP BY DATE(Cobranca)
ORDER BY data;
```

---

## ✅ Resumo

| Recurso | Descrição |
|---------|-----------|
| **Coluna** | `Cobranca` (DATE) |
| **Objetivo** | Data ideal para follow-up/cobrança |
| **Lógica** | Primeira parcela pendente (Atraso/Aberto/Ativo) ou última parcela (Quitado) |
| **Uso Principal** | Workflows de cobrança, notificações, dashboards |
| **Vantagem** | Sempre mostra a data mais urgente, facilitando priorização |

---

## 🚀 Próximos Passos

1. ✅ Atualizar a procedure no banco (arquivo `mysql_query_FASTEST_FILTROS.sql`)
2. ✅ Testar: `CALL afs_receitas_consolidadas_filtrada(NULL);`
3. ✅ Verificar a nova coluna `Cobranca` no resultado
4. ✅ Implementar workflows de notificação baseados em `Cobranca`
5. ✅ Criar dashboards ordenados por urgência de cobrança

---

**A coluna Cobranca torna sua gestão de cobrança muito mais eficiente!** 🎉
