# 🔍 Como Usar Filtros de Status na Query

Você tem **2 versões** da procedure:

1. **afs_receitas_consolidadas** - Versão atual (sem filtros)
2. **afs_receitas_consolidadas_filtrada** - Nova versão COM filtros ⭐

---

## 📌 Versão COM Filtros (Recomendada)

**Arquivo**: `mysql_query_FASTEST_FILTROS.sql`

### Como Instalar:

```sql
-- 1. Copie TODO o conteúdo do arquivo mysql_query_FASTEST_FILTROS.sql
-- 2. Execute no MySQL Workbench
-- 3. A procedure será criada automaticamente
```

---

## 🎯 Como Usar os Filtros

### Sintaxe:
```sql
CALL dagiel67_central_mdzd.afs_receitas_consolidadas_filtrada('FILTRO');
```

### Valores de Status Disponíveis:

| Status | Descrição |
|--------|-----------|
| **Atraso** | Contratos com parcelas vencidas (atrasadas) |
| **Aberto** | Contratos com parcelas futuras, sem nenhum pagamento ainda |
| **Ativo** | Contratos com parcelas futuras e já teve pagamentos |
| **Quitado** | Contratos totalmente pagos |

---

## 📝 Exemplos de Uso

### 1️⃣ Todos os Registros (Sem Filtro)
```sql
CALL dagiel67_central_mdzd.afs_receitas_consolidadas_filtrada(NULL);
```
**Resultado**: Retorna TODOS os 5.560 contratos

---

### 2️⃣ Apenas Contratos em Atraso
```sql
CALL dagiel67_central_mdzd.afs_receitas_consolidadas_filtrada('Atraso');
```
**Resultado**: Só contratos com parcelas vencidas

---

### 3️⃣ Apenas Contratos Abertos (Sem Pagamento)
```sql
CALL dagiel67_central_mdzd.afs_receitas_consolidadas_filtrada('Aberto');
```
**Resultado**: Só contratos novos sem nenhum pagamento

---

### 4️⃣ Filtrar Múltiplos Status (Atraso OU Aberto)
```sql
CALL dagiel67_central_mdzd.afs_receitas_consolidadas_filtrada('Atraso,Aberto');
```
**Resultado**: Contratos em Atraso OU Aberto
**Uso**: Ver todos os contratos problemáticos

---

### 5️⃣ Contratos Ativos ou Quitados
```sql
CALL dagiel67_central_mdzd.afs_receitas_consolidadas_filtrada('Ativo,Quitado');
```
**Resultado**: Contratos em dia ou já pagos
**Uso**: Ver situação positiva

---

### 6️⃣ Apenas Quitados
```sql
CALL dagiel67_central_mdzd.afs_receitas_consolidadas_filtrada('Quitado');
```
**Resultado**: Só contratos totalmente pagos

---

## 🚀 Exemplos Práticos de Negócio

### Dashboard de Cobrança
```sql
-- Ver tudo que está pendente (Atraso + Aberto)
CALL dagiel67_central_mdzd.afs_receitas_consolidadas_filtrada('Atraso,Aberto');
```

### Relatório de Inadimplência
```sql
-- Apenas em atraso
CALL dagiel67_central_mdzd.afs_receitas_consolidadas_filtrada('Atraso');
```

### Contratos em Andamento
```sql
-- Ativos (em dia e pagando)
CALL dagiel67_central_mdzd.afs_receitas_consolidadas_filtrada('Ativo');
```

### Relatório Financeiro Completo
```sql
-- Todos os contratos não quitados
CALL dagiel67_central_mdzd.afs_receitas_consolidadas_filtrada('Atraso,Aberto,Ativo');
```

---

## 📊 Performance com Filtros

| Filtro | Registros Esperados | Tempo |
|--------|---------------------|-------|
| NULL (todos) | 5.560 | 2-5s |
| 'Atraso' | ~500-1000 | 1-3s ⚡ |
| 'Aberto' | ~200-500 | 1-2s ⚡ |
| 'Ativo' | ~2000-3000 | 2-4s |
| 'Quitado' | ~2000-3000 | 2-4s |
| 'Atraso,Aberto' | ~700-1500 | 1-3s ⚡ |

**Nota**: Filtros reduzem o tempo de **fetching** porque retornam menos dados!

---

## 🔧 Integração com Aplicações

### PHP
```php
// Filtro único
$stmt = $pdo->prepare("CALL afs_receitas_consolidadas_filtrada(?)");
$stmt->execute(['Atraso']);
$resultados = $stmt->fetchAll();

// Múltiplos filtros
$filtros = ['Atraso', 'Aberto'];
$stmt->execute([implode(',', $filtros)]);
```

### Python
```python
import mysql.connector

# Filtro único
cursor.callproc('afs_receitas_consolidadas_filtrada', ['Atraso'])
for result in cursor.stored_results():
    data = result.fetchall()

# Múltiplos filtros
filtros = 'Atraso,Aberto'
cursor.callproc('afs_receitas_consolidadas_filtrada', [filtros])
```

### Node.js
```javascript
// Filtro único
connection.query(
  'CALL afs_receitas_consolidadas_filtrada(?)',
  ['Atraso'],
  (err, results) => {
    console.log(results[0]); // Primeira tabela = dados
  }
);

// Múltiplos filtros
const filtros = ['Atraso', 'Aberto'].join(',');
connection.query('CALL afs_receitas_consolidadas_filtrada(?)', [filtros], ...);
```

### C# / .NET
```csharp
using (var cmd = new MySqlCommand("afs_receitas_consolidadas_filtrada", conn))
{
    cmd.CommandType = CommandType.StoredProcedure;
    cmd.Parameters.AddWithValue("p_filtro_status", "Atraso,Aberto");

    using (var reader = cmd.ExecuteReader())
    {
        while (reader.Read())
        {
            // Processar dados
        }
    }
}
```

---

## ⚙️ Onde o Filtro é Aplicado

O filtro é aplicado **no final da query**, na linha **169-186** do arquivo:

```sql
WHERE a.id_cliente IS NOT NULL
  -- APLICAR FILTRO DE STATUS (AQUI!)
  AND (
    v_usar_filtro = FALSE  -- Se NULL, retorna tudo
    OR
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
```

### Como Funciona:

1. **Sem filtro** (`NULL`): Retorna todos os registros
2. **Com filtro** (`'Atraso'`): Aplica `WHERE Status = 'Atraso'`
3. **Múltiplos** (`'Atraso,Aberto'`): Aplica `WHERE Status IN ('Atraso', 'Aberto')`

---

## ❓ FAQ

### Posso adicionar outros filtros (cliente, data, etc.)?

**Sim!** Para adicionar mais filtros, edite a procedure:

#### Exemplo: Filtrar por Cliente

```sql
-- Altere a assinatura da procedure (linha 15):
CREATE PROCEDURE `afs_receitas_consolidadas_filtrada`(
  IN p_filtro_status VARCHAR(500),
  IN p_id_cliente VARCHAR(100)  -- NOVO PARÂMETRO
)

-- Adicione na cláusula WHERE final (linha 169):
WHERE a.id_cliente IS NOT NULL
  AND (p_id_cliente IS NULL OR a.id_cliente = p_id_cliente)  -- NOVO FILTRO
  AND (
    v_usar_filtro = FALSE
    ...
  );

-- Uso:
CALL afs_receitas_consolidadas_filtrada('Atraso', '123-456');
```

#### Exemplo: Filtrar por Data

```sql
-- Adicione parâmetros:
IN p_data_inicio DATE,
IN p_data_fim DATE

-- Adicione no WHERE:
AND (p_data_inicio IS NULL OR a.Compra >= p_data_inicio)
AND (p_data_fim IS NULL OR a.Compra <= p_data_fim)

-- Uso:
CALL afs_receitas_consolidadas_filtrada('Atraso', '2024-01-01', '2024-12-31');
```

---

### Como voltar para a versão sem filtros?

```sql
-- Basta chamar a procedure original:
CALL dagiel67_central_mdzd.afs_receitas_consolidadas();
```

As duas procedures **coexistem** no banco. Use a que preferir!

---

### O filtro deixa a query mais lenta?

**Não!** Na verdade, pode deixar **mais rápida** porque:
- Menos registros retornados = menos tempo de fetching
- Índice em `Status` otimiza a filtragem
- Filtro aplicado só no final (dados já agregados)

---

### Posso criar uma view para cada filtro?

**Sim!** Exemplo:

```sql
-- View de contratos em atraso
CREATE VIEW vw_contratos_atraso AS
SELECT * FROM (
  CALL afs_receitas_consolidadas_filtrada('Atraso')
);

-- Uso:
SELECT * FROM vw_contratos_atraso;
```

**Mas atenção**: Views com procedures podem ter limitações no MySQL.
**Alternativa melhor**: Criar tabelas materializadas (ver QUAL_QUERY_USAR.md)

---

## 🎓 Resumo

| Situação | Comando |
|----------|---------|
| **Todos os dados** | `CALL afs_receitas_consolidadas_filtrada(NULL);` |
| **Só Atraso** | `CALL afs_receitas_consolidadas_filtrada('Atraso');` |
| **Atraso ou Aberto** | `CALL afs_receitas_consolidadas_filtrada('Atraso,Aberto');` |
| **Não Quitados** | `CALL afs_receitas_consolidadas_filtrada('Atraso,Aberto,Ativo');` |
| **Só Quitados** | `CALL afs_receitas_consolidadas_filtrada('Quitado');` |

---

## 💡 Próximos Passos

1. ✅ Execute `mysql_query_FASTEST_FILTROS.sql` para criar a procedure
2. ✅ Teste com: `CALL afs_receitas_consolidadas_filtrada('Atraso');`
3. ✅ Integre na sua aplicação
4. ✅ Aproveite os filtros! 🚀

Se precisar de mais filtros ou tiver dúvidas, me avisa! 💪
