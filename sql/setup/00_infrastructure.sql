-- =============================================================================
-- CA Vida POC - Infrastructure Setup
-- =============================================================================
-- Run this script FIRST to create all required objects before pipeline execution.
-- Adjust warehouse sizes, storage integration, and role names as needed.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. DATABASE
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE DATABASE CAVIDA_POC;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. SCHEMAS
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE SCHEMA CAVIDA_POC.EXTRACTION
  COMMENT = 'Raw CSV ingestion layer (17 transient tables)';

CREATE OR REPLACE SCHEMA CAVIDA_POC.STAGING
  COMMENT = 'Business transformations (window functions, joins, dedup)';

CREATE OR REPLACE SCHEMA CAVIDA_POC.DW
  COMMENT = 'Data Warehouse: SCD Type 2 tables with MD5 change detection';

CREATE OR REPLACE SCHEMA CAVIDA_POC.POC_LOOK
  COMMENT = 'Reference/lookup dimensions (pre-loaded)';

CREATE OR REPLACE SCHEMA CAVIDA_POC.ORCHESTRATION
  COMMENT = 'Pipeline orchestration: Tasks DAG + monitoring';

CREATE OR REPLACE SCHEMA CAVIDA_POC.ANALYTICS
  COMMENT = 'Value-add layer: Semantic View, Agent, Streamlit, Governance';

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. WAREHOUSES
-- ─────────────────────────────────────────────────────────────────────────────
-- Production warehouse (recommended for full pipeline)
CREATE OR REPLACE WAREHOUSE CAVIDA_POC_WH
  WAREHOUSE_SIZE = 'LARGE'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Primary pipeline warehouse - Large Gen2';

-- Cost-optimized alternatives
CREATE OR REPLACE WAREHOUSE CAVIDA_XS
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Cost-optimized: 1 credit/hr, pipeline in ~1h20m';

CREATE OR REPLACE WAREHOUSE CAVIDA_S
  WAREHOUSE_SIZE = 'SMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Balanced: 2 credits/hr, pipeline in ~48m';

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. FILE FORMATS
-- ─────────────────────────────────────────────────────────────────────────────
USE SCHEMA CAVIDA_POC.EXTRACTION;

-- Primary file format for all source CSVs (ISO-8859-1 / Latin1 encoding)
CREATE OR REPLACE FILE FORMAT CSV_LATIN1
  TYPE = 'CSV'
  FIELD_DELIMITER = ','
  RECORD_DELIMITER = '\n'
  SKIP_HEADER = 1
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  NULL_IF = ('', '.')
  EMPTY_FIELD_AS_NULL = TRUE
  ENCODING = 'ISO-8859-1'
  ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE
  MULTI_LINE = TRUE
  COMMENT = 'SAS DSD/MISSOVER equivalent: latin1 encoding, quoted fields, empty=null, dot=null';

-- Special format for RECIBO table (has SAS overflow markers **)
CREATE OR REPLACE FILE FORMAT CSV_LATIN1_RECIBO
  TYPE = 'CSV'
  FIELD_DELIMITER = ','
  RECORD_DELIMITER = '\n'
  SKIP_HEADER = 1
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  NULL_IF = ('', '.', '**', '***', '****', '*****', '******', '*******')
  EMPTY_FIELD_AS_NULL = TRUE
  ENCODING = 'ISO-8859-1'
  ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE
  MULTI_LINE = TRUE
  COMMENT = 'RECIBO-specific: adds SAS overflow markers ** to NULL_IF';

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. INTERNAL STAGE (for CSV source files)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE STAGE CAVIDA_POC.EXTRACTION.INPUT_DATA
  DIRECTORY = (ENABLE = TRUE)
  COMMENT = 'Stage for 17 CSV source files (32GB total, latin1 encoded)';

-- Upload files to stage (run from CLI):
-- snow stage copy /path/to/csv_files/* @CAVIDA_POC.EXTRACTION.INPUT_DATA/
-- Or via PUT:
-- PUT file:///path/to/data/*.csv @CAVIDA_POC.EXTRACTION.INPUT_DATA/ AUTO_COMPRESS=TRUE;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. STREAMLIT STAGE
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE STAGE CAVIDA_POC.ANALYTICS.STREAMLIT_STAGE
  DIRECTORY = (ENABLE = TRUE)
  ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE')
  COMMENT = 'Stage for Streamlit in Snowflake app files';

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. SESSION PARAMETERS (for pipeline execution)
-- ─────────────────────────────────────────────────────────────────────────────
ALTER SESSION SET USE_CACHED_RESULT = FALSE;
ALTER SESSION SET TIMEZONE = 'Europe/Lisbon';

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. MONITORING TABLE (for Task DAG alerts)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS CAVIDA_POC.ORCHESTRATION.PIPELINE_MONITOR_LOG (
  LOG_ID INTEGER AUTOINCREMENT,
  CHECK_TYPE VARCHAR(100),
  STATUS VARCHAR(20),
  METRIC_VALUE FLOAT,
  THRESHOLD_VALUE FLOAT,
  AI_SUMMARY VARCHAR(2000),
  DETAILS VARIANT,
  CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
