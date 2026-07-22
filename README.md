# CA Vida POC — Snowflake Implementation

## Overview

Proof of Concept for **CA Vida** (Crédito Agrícola Seguros de Vida) — migrating the SAS-based insurance data pipeline to Snowflake. The POC processes life insurance policy and exposure data through a complete ELT pipeline with SCD Type 2 historization.

**Result**: Full pipeline reconciliation achieved — 24,168,835 records matching SAS output exactly.

---

## Architecture

```
┌─────────────┐     ┌──────────────┐     ┌───────────────┐     ┌──────────────┐
│  S3 Source  │────▶│  EXTRACTION  │────▶│   STAGING     │────▶│     DW       │
│  (CSV/GZ)   │     │  (17 COPY)   │     │  (Transform)  │     │  (SCD2 MERGE)│
└─────────────┘     └──────────────┘     └───────────────┘     └──────────────┘
                                                                       │
                                                                       ▼
                                                          ┌────────────────────┐
                                                          │    ANALYTICS       │
                                                          │  • Semantic View   │
                                                          │  • Cortex Agent    │
                                                          │  • Streamlit App   │
                                                          │  • Governance      │
                                                          └────────────────────┘
```

| Layer | Schema | Purpose |
|-------|--------|---------|
| Extraction | `EXTRACTION` | Raw CSV ingestion via COPY INTO (17 parallel jobs) |
| Staging | `STAGING` | Business transformations (window functions, dedup, SCD logic) |
| Data Warehouse | `DW` | SCD Type 2 tables with MD5 change detection |
| Analytics | `ANALYTICS` | Semantic View, Cortex Agent, Streamlit, Masking |
| Orchestration | `ORCHESTRATION` | Task DAG, AI-powered alerts |

---

## Repository Structure

```
cavida-poc-snowflake/
├── README.md
├── sql/
│   ├── pipeline/              # Core ELT pipeline (extraction → staging → DW)
│   │   ├── LOAD_LIFEUNITOFEXPOSURE.sql
│   │   ├── LOAD_LIFEPOLICYTRANS.sql
│   │   ├── INSPOL_LIFEUNITOFEXPOSURE_003.sql  (staging transforms)
│   │   ├── INSPOL_LIFEUNITOFEXPOSURE_005.sql  (SCD2 load)
│   │   ├── INSPOL_LIFEPOLICYTRANS_001.sql
│   │   ├── INSPOL_LIFEPOLICYTRANS_002.sql
│   │   └── INSPOL_LIFEPOLICYTRANS_003.sql
│   ├── semantic_view/         # Cortex Analyst semantic model
│   │   ├── INSURANCE_INTELLIGENCE_semantic_model.yaml
│   │   └── create_semantic_view.sql
│   ├── agent/                 # Cortex Agent (PT-PT)
│   │   └── create_agent.sql
│   ├── governance/            # Tag-based masking policies
│   │   └── create_masking_policy.sql
│   └── orchestration/         # Task DAG with Cortex LLM alerts
│       └── create_task_dag.sql
├── streamlit/
│   └── portfolio_risk_monitor/  # Streamlit in Snowflake app
│       ├── streamlit_app.py
│       ├── snowflake.yml
│       └── environment.yml
├── dbt/                       # dbt models (Solvency II reporting - future)
│   └── (dbt project structure)
└── docs/
    ├── CHANGE_LOG_UOE_SCD2_DEDUP.md
    └── slides/
        ├── cavida_poc_results_slides.html
        ├── cavida_poc_results_slides.pdf
        ├── value_add_demo_slides.html
        ├── TALK_TRACK.html
        └── DEMO_FLOW.html
```

---

## POC Results — Performance Benchmark

| Warehouse | Size | Credits/hr | Pipeline Time | Total Cost | vs. SAS (8h) |
|-----------|------|-----------|---------------|-----------|--------------|
| COMPUTE_WH | Large | $8/hr | 25m 12s | $3.36 | **95% faster** |
| CAVIDA_XS | X-Small | $1/hr | 1h 20m 25s | $1.34 | **60% cheaper** |
| CAVIDA_S | Small | $2/hr | 47m 59s | $1.60 | **52% cheaper** |

**Key metrics:**
- Records processed: 24,168,835 (LIFE_UNIT_OF_EXPOSURE) + 19,459,571 (LIFE_POLICY_TRANS)
- SCD2 reconciliation: exact match with SAS output
- Deduplication: 3 records removed per business rule (documented in CHANGE_LOG)

---

## Value-Add Features (Beyond POC Scope)

| Feature | Object | Description |
|---------|--------|-------------|
| **Semantic View** | `ANALYTICS.INSURANCE_INTELLIGENCE` | Natural language queries over insurance data (5 tables, 7 metrics) |
| **Cortex Agent** | `ANALYTICS.INSURANCE_AGENT` | AI assistant in PT-PT for portfolio analysis |
| **Streamlit App** | `ANALYTICS.PORTFOLIO_RISK_MONITOR` | Real-time risk dashboard (anomalies, concentration, persistency) |
| **Data Governance** | `ANALYTICS.PII_TYPE` + `PII_MASK_STRING` | Tag-based dynamic masking for GDPR |
| **AI Monitoring** | `ORCHESTRATION.DQ_CHECK_ROOT` (DAG) | Cortex LLM-powered alert generation |
| **dbt SLV2** | `dbt/` | Solvency II reporting models (future phase) |

---

## Deployment

### Prerequisites
- Snowflake Business Critical edition
- `ACCOUNTADMIN` role (or equivalent with schema-level grants)
- Warehouse: any size (XS recommended for cost optimization)

### Quick Start

```sql
-- 1. Run pipeline
USE WAREHOUSE COMPUTE_WH;
-- Execute sql/pipeline/ scripts in order

-- 2. Deploy analytics layer
USE SCHEMA CAVIDA_POC.ANALYTICS;
-- Execute sql/semantic_view/create_semantic_view.sql
-- Execute sql/agent/create_agent.sql
-- Execute sql/governance/create_masking_policy.sql

-- 3. Deploy monitoring
-- Execute sql/orchestration/create_task_dag.sql

-- 4. Deploy Streamlit app
PUT file://streamlit/portfolio_risk_monitor/streamlit_app.py @CAVIDA_POC.ANALYTICS.STREAMLIT_STAGE/ AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
PUT file://streamlit/portfolio_risk_monitor/environment.yml @CAVIDA_POC.ANALYTICS.STREAMLIT_STAGE/ AUTO_COMPRESS=FALSE OVERWRITE=TRUE;

CREATE OR REPLACE STREAMLIT CAVIDA_POC.ANALYTICS.PORTFOLIO_RISK_MONITOR
  ROOT_LOCATION = '@CAVIDA_POC.ANALYTICS.STREAMLIT_STAGE'
  MAIN_FILE = 'streamlit_app.py'
  QUERY_WAREHOUSE = 'COMPUTE_WH';
```

---

## Snowflake Features Utilized

| Feature | Usage |
|---------|-------|
| COPY INTO (parallel) | 17 parallel extraction jobs from S3 |
| Window Functions (LAG, ROW_NUMBER, QUALIFY) | SAS RETAIN/BY-group replacement |
| MERGE (SCD Type 2) | Atomic versioned history with MD5 change detection |
| Cortex Analyst (Semantic View) | Natural language → SQL |
| Cortex Agent | Conversational AI in PT-PT |
| Cortex LLM (COMPLETE) | AI-powered monitoring alerts |
| Streamlit in Snowflake | Portfolio risk dashboard |
| Tag-based Masking | Dynamic PII protection |
| Tasks (DAG) | Native orchestration with dependencies |
| Transient Tables | Zero Time Travel overhead for staging |

---

## Contact

**Snowflake Solution Engineering** — Iberia Team
