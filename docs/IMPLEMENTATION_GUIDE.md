# CA Vida POC — Guia de Implementação

## Pré-requisitos

| Requisito | Valor |
|-----------|-------|
| Edição Snowflake | Business Critical |
| Role | ACCOUNTADMIN (ou equivalente com grants ao nível de schema) |
| Warehouse mínimo | X-Small (1 credit/hr) |
| Warehouse recomendado | Large (8 credits/hr) para execução rápida |
| Dados fonte | 17 ficheiros CSV (codificação ISO-8859-1), ~32GB total |
| Região | Qualquer (POC testado em Azure West Europe) |

---

## Passo 1: Criar Infraestrutura

Execute o script de setup que cria a base de dados, schemas, warehouses, file formats e stages:

```sql
-- Executar:
sql/setup/00_infrastructure.sql
```

Este script cria:
- Base de dados `CAVIDA_POC`
- 6 schemas: EXTRACTION, STAGING, DW, POC_LOOK, ORCHESTRATION, ANALYTICS
- 3 warehouses: CAVIDA_POC_WH (Large), CAVIDA_XS (X-Small), CAVIDA_S (Small)
- 2 file formats: CSV_LATIN1, CSV_LATIN1_RECIBO
- 2 stages: INPUT_DATA (dados CSV), STREAMLIT_STAGE (app Streamlit)
- Tabela de monitorização: PIPELINE_MONITOR_LOG

---

## Passo 2: Carregar Dados Fonte

Fazer upload dos 17 ficheiros CSV para o stage interno:

```bash
# Opção A: Snow CLI
snow stage copy /caminho/para/dados/ACTA00/*.csv @CAVIDA_POC.EXTRACTION.INPUT_DATA/ACTA00/
snow stage copy /caminho/para/dados/ACTA03/*.csv @CAVIDA_POC.EXTRACTION.INPUT_DATA/ACTA03/
# ... repetir para os 17 ficheiros

# Opção B: SQL PUT
PUT file:///caminho/para/dados/ACTA00/*.csv @CAVIDA_POC.EXTRACTION.INPUT_DATA/ACTA00/ AUTO_COMPRESS=TRUE;
PUT file:///caminho/para/dados/MOVIML/*.csv @CAVIDA_POC.EXTRACTION.INPUT_DATA/MOVIML/ AUTO_COMPRESS=TRUE;
# ... etc.
```

Os 17 ficheiros fonte são:
| # | Ficheiro | Rows | Descrição |
|---|----------|------|-----------|
| 1 | ACTA00 | 11.4M | Transações contabilísticas |
| 2 | ACTA03 | 11.1M | Detalhes contabilísticos |
| 3 | ACTA0P | 245K | Parâmetros contabilísticos |
| 4 | APOL00 | 1.4M | Apólices |
| 5 | APOL03 | 1.1M | Detalhes de apólices |
| 6 | APOL0PH | 142K | Histórico de apólices |
| 7 | APOL0P | 12.5K | Parâmetros de apólices |
| 8 | APOLPA | 8.5M | Ligações apólice-pessoa |
| 9 | ENTREL | 2.2M | Relações entre entidades |
| 10 | ENTVIN | 8.0M | Vínculos de entidades |
| 11 | EVENTO | 45.6M | Eventos (maior tabela de extração) |
| 12 | MOPEC1 | 12.1M | Detalhes de movimentos |
| 13 | MOVIML | 27.9M | Movimentos |
| 14 | RECI0X | 1.6M | Recibos extra |
| 15 | RECIBO | 47.4M | Recibos (usa formato especial) |
| 16 | RECPRO | 256K | Processamento de recibos |
| 17 | RECREL | 960K | Relações de recibos |

**Total: ~190 milhões de linhas**

---

## Passo 3: Executar Extração (COPY INTO)

```sql
-- Executar:
sql/setup/01_extraction_tables.sql
```

Este script cria 17 tabelas TRANSIENT e executa COPY INTO em paralelo. Tempo esperado: ~45 segundos com warehouse Large.

---

## Passo 4: Carregar Dimensões de Referência (POC_LOOK)

As tabelas de referência devem ser pré-carregadas no schema POC_LOOK:
- `INSURANCE_POLICY` — Apólices (com POLICY_RK como chave surrogate)
- `X_INSURANCE_PROPOSAL` — Propostas
- `COVERAGE` — Coberturas
- `PRODUCT_CATEGORY` — Categorias de produto
- `EMPLOYEE` — Colaboradores
- `X_BUSINESS_STRUCTURE` — Estrutura comercial

Estas tabelas são fornecidas pelo cliente ou criadas a partir dos dados de referência.

---

## Passo 5: Executar Pipeline de Transformação (Staging)

Os scripts devem ser executados pela seguinte ordem:

### LIFE_UNIT_OF_EXPOSURE (UOE):
```sql
-- 1. sql/pipeline/INSPOL_LIFEUNITOFEXPOSURE_003.sql
--    Transforma dados brutos: FULL JOIN + RIGHT JOIN, window functions
--    Output: STAGING.INSPOL_LIFEUNITOFEXPOSURE_003 (~2M rows)

-- 2. sql/pipeline/INSPOL_LIFEUNITOFEXPOSURE_005.sql
--    LAG/LEAD window functions, parity logic, version zero
--    Output: STAGING.INSPOL_LIFEUNITOFEXPOSURE_005 (~24.2M rows)
```

### LIFE_POLICY_TRANS (LPT):
```sql
-- 3. sql/pipeline/INSPOL_LIFEPOLICYTRANS_001.sql
--    Row explosion (1→6 UNION ALL) + 4-table join
--    Output: STAGING.INSPOL_LIFEPOLICYTRANS_001 (~149.7M rows)

-- 4. sql/pipeline/INSPOL_LIFEPOLICYTRANS_002.sql
--    Employee lookup + X_PROCESSED_FLG state machine
--    Output: STAGING.INSPOL_LIFEPOLICYTRANS_002 (~149.7M rows)

-- 5. sql/pipeline/INSPOL_LIFEPOLICYTRANS_003.sql
--    Append status-2 rows + RECREL + filter
--    Output: STAGING.INSPOL_LIFEPOLICYTRANS_003 (~169.3M rows)
```

Tempo total de transformação: ~3 minutos com warehouse Large.

---

## Passo 6: Executar Carga no Data Warehouse (SCD Type 2)

```sql
-- 6. sql/pipeline/LOAD_LIFEUNITOFEXPOSURE.sql
--    SCD2 com MD5 change detection, 4 lookup joins, DENSE_RANK
--    Output: DW.LIFE_UNIT_OF_EXPOSURE (24,168,835 rows)

-- 7. sql/pipeline/LOAD_LIFEPOLICYTRANS.sql
--    Splitter: Y→HIST (169.3M), N→CURRENT (55.5K)
--    Output: DW.LIFE_POLICY_TRANS + DW.X_LIFE_POLICY_TRANS_HIST
```

---

## Passo 7: Verificar Reconciliação

```sql
-- Verificar contagens finais
SELECT 'LIFE_UNIT_OF_EXPOSURE' AS TABLE_NAME, COUNT(*) AS ROWS FROM CAVIDA_POC.DW.LIFE_UNIT_OF_EXPOSURE
UNION ALL
SELECT 'LIFE_POLICY_TRANS', COUNT(*) FROM CAVIDA_POC.DW.LIFE_POLICY_TRANS
UNION ALL
SELECT 'X_LIFE_POLICY_TRANS_HIST', COUNT(*) FROM CAVIDA_POC.DW.X_LIFE_POLICY_TRANS_HIST;

-- Resultado esperado:
-- LIFE_UNIT_OF_EXPOSURE:    24,168,835
-- LIFE_POLICY_TRANS:        56,597
-- X_LIFE_POLICY_TRANS_HIST: 169,264,776
```

---

## Passo 8: Deploy da Camada Analítica (Value-Add)

### 8a. Semantic View
```sql
-- Executar: sql/semantic_view/create_semantic_view.sql
-- Ou usar YAML diretamente:
SELECT SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML(
  'CAVIDA_POC.ANALYTICS.INSURANCE_INTELLIGENCE',
  (SELECT TO_VARCHAR(FILE_CONTENT) FROM @CAVIDA_POC.ANALYTICS.STREAMLIT_STAGE/INSURANCE_INTELLIGENCE_semantic_model.yaml)
);
```

### 8b. Cortex Agent
```sql
-- Executar: sql/agent/create_agent.sql
-- Cria agente conversacional em PT-PT
```

### 8c. Governance (Masking)
```sql
-- Executar: sql/governance/create_masking_policy.sql
-- Cria tag PII_TYPE + masking policy dinâmica
```

### 8d. Monitoring DAG
```sql
-- Executar: sql/orchestration/create_task_dag.sql
-- Task DAG com alertas AI (Cortex LLM)
```

### 8e. Streamlit App
```sql
-- Upload ficheiros
PUT file://streamlit/portfolio_risk_monitor/streamlit_app.py 
    @CAVIDA_POC.ANALYTICS.STREAMLIT_STAGE/ AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
PUT file://streamlit/portfolio_risk_monitor/environment.yml 
    @CAVIDA_POC.ANALYTICS.STREAMLIT_STAGE/ AUTO_COMPRESS=FALSE OVERWRITE=TRUE;

-- Criar app
CREATE OR REPLACE STREAMLIT CAVIDA_POC.ANALYTICS.PORTFOLIO_RISK_MONITOR
  ROOT_LOCATION = '@CAVIDA_POC.ANALYTICS.STREAMLIT_STAGE'
  MAIN_FILE = 'streamlit_app.py'
  QUERY_WAREHOUSE = 'COMPUTE_WH'
  COMMENT = 'Portfolio Risk Monitor: anomalias, concentração, persistência';
```

---

## Passo 9: Verificação Final

```sql
-- Listar todos os objetos criados
SHOW OBJECTS IN DATABASE CAVIDA_POC;

-- Verificar Semantic View
DESCRIBE SEMANTIC VIEW CAVIDA_POC.ANALYTICS.INSURANCE_INTELLIGENCE;

-- Verificar Agent
SHOW AGENTS IN SCHEMA CAVIDA_POC.ANALYTICS;

-- Verificar Streamlit
SHOW STREAMLITS IN SCHEMA CAVIDA_POC.ANALYTICS;

-- Verificar Tasks
SHOW TASKS IN SCHEMA CAVIDA_POC.ORCHESTRATION;

-- Verificar Masking
SELECT * FROM TABLE(INFORMATION_SCHEMA.POLICY_REFERENCES(
  REF_ENTITY_NAME => 'CAVIDA_POC.ANALYTICS.PII_TYPE',
  REF_ENTITY_DOMAIN => 'TAG'
));
```

---

## Notas de Implementação SAS→SQL

### Conversão de Padrões SAS para Snowflake SQL

| Padrão SAS | Equivalente Snowflake |
|-----------|----------------------|
| `RETAIN` + BY-group | `LAG()` / `LEAD()` window functions |
| `PROC SORT NODUPKEY` | `QUALIFY ROW_NUMBER() OVER(...) = 1` |
| `cats(put(var, zN.))` | `LPAD(var::VARCHAR, N, '0')` |
| `IF FIRST.key` | `ROW_NUMBER() OVER(PARTITION BY key ORDER BY ...)` |
| Missing numeric (.) | `NULL` (handled by NULL_IF in file format) |
| Missing character ('') | `NULL` (EMPTY_FIELD_AS_NULL = TRUE) |
| `datetime()` | `CURRENT_TIMESTAMP()` (pin with SET variable) |
| `01JAN5999` | `'5999-01-01 00:00:00'::TIMESTAMP_NTZ` |
| `OUTPUT` multiple datasets | `UNION ALL` ou tabelas separadas |
| `MERGE` (SAS data step) | `FULL JOIN` / `LEFT JOIN` |
| `SET` (append datasets) | `UNION ALL` |

### Considerações de Paridade

1. **NULL handling**: SAS trata missing diferente do SQL NULL — usar `COALESCE()` nos WHERE
2. **Numeric missing < any number**: Usar `COALESCE(col, -1) < N`
3. **Character missing != 'X'**: Usar `COALESCE(col, '') != 'X'`
4. **DATE construction**: `LPAD(year,4,'0') || '-' || LPAD(month,2,'0') || '-' || LPAD(day,2,'0')`

---

## Benchmark de Performance

| Warehouse | Créditos/hr | Tempo Pipeline | Custo Total | vs SAS (8h) |
|-----------|-------------|----------------|------------|-------------|
| Large | 8 | 25m 12s | $3.36 | 95% mais rápido |
| X-Small | 1 | 1h 20m 25s | $1.34 | 60% mais barato |
| Small | 2 | 47m 59s | $1.60 | 52% mais barato |

**Nota**: Edição Business Critical, Azure West Europe, $5.50/crédito.

---

## Resolução de Problemas

| Problema | Causa | Solução |
|----------|-------|---------|
| SUM overflow (100058) | NUMBER(38,6) excede precisão | Usar `SUM(col::FLOAT)` |
| Row count mismatch | Diferença no tratamento de NULLs | Verificar COALESCE nos WHERE |
| RECIBO parsing errors | Overflow markers (**) no CSV | Usar CSV_LATIN1_RECIBO format |
| Streamlit `hide_index` error | Versão SiS não suporta | Remover `hide_index=True` |
| `st.connection` error | SiS usa Snowpark session | Usar `get_active_session()` |
| `plotly` not found | Packages não instalados | Criar `environment.yml` com `channels: [snowflake]` |
