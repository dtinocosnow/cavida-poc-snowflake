-- =============================================================================
-- CA Vida POC - AI-Powered Monitoring Task DAG
-- =============================================================================
-- Implements automated data quality monitoring using Cortex LLM for 
-- intelligent alert generation in Portuguese.
-- =============================================================================

USE SCHEMA CAVIDA_POC.ORCHESTRATION;

-- 1. Root task - Data Quality Check (runs every 6 hours)
CREATE OR REPLACE TASK DQ_CHECK_ROOT
  WAREHOUSE = COMPUTE_WH
  SCHEDULE = 'USING CRON 0 */6 * * * Europe/Lisbon'
  COMMENT = 'Root task for data quality monitoring DAG'
AS
  SELECT 1; -- Anchor task

-- 2. Premium Anomaly Detection (child of root)
CREATE OR REPLACE TASK DQ_PREMIUM_ANOMALY
  WAREHOUSE = COMPUTE_WH
  AFTER DQ_CHECK_ROOT
  COMMENT = 'Detects anomalies in premium amounts using statistical thresholds'
AS
  BEGIN
    LET v_anomaly_count INTEGER;
    LET v_alert_msg STRING;
    
    -- Detect premiums > 3 standard deviations from mean
    SELECT COUNT(*) INTO :v_anomaly_count
    FROM CAVIDA_POC.DW.LIFE_UNIT_OF_EXPOSURE
    WHERE ANNUAL_PREMIUM_AMT > (
      SELECT AVG(ANNUAL_PREMIUM_AMT) + 3 * STDDEV(ANNUAL_PREMIUM_AMT)
      FROM CAVIDA_POC.DW.LIFE_UNIT_OF_EXPOSURE
    )
    AND DW_CURRENT_FLAG = 'Y';
    
    IF (:v_anomaly_count > 0) THEN
      -- Use Cortex LLM to generate intelligent alert in Portuguese
      SELECT SNOWFLAKE.CORTEX.COMPLETE('mistral-large2',
        'Gera um alerta conciso em português de Portugal sobre ' || :v_anomaly_count || 
        ' registos com prémios anómalos detectados no portfolio de seguros de vida. ' ||
        'Inclui recomendação de ação.'
      ) INTO :v_alert_msg;
      
      -- Log the alert
      INSERT INTO CAVIDA_POC.ORCHESTRATION.DQ_ALERTS (ALERT_TYPE, ALERT_MSG, RECORD_COUNT, CREATED_AT)
      VALUES ('PREMIUM_ANOMALY', :v_alert_msg, :v_anomaly_count, CURRENT_TIMESTAMP());
    END IF;
  END;

-- 3. Persistency Alert (child of root)
CREATE OR REPLACE TASK DQ_PERSISTENCY_ALERT
  WAREHOUSE = COMPUTE_WH
  AFTER DQ_CHECK_ROOT
  COMMENT = 'Monitors policy lapse rates and generates alerts'
AS
  BEGIN
    LET v_lapse_rate FLOAT;
    LET v_alert_msg STRING;
    
    -- Calculate current lapse rate
    SELECT COUNT(CASE WHEN POLICY_STATUS_CD = 'LAPSED' THEN 1 END)::FLOAT / 
           NULLIF(COUNT(*), 0) * 100
    INTO :v_lapse_rate
    FROM CAVIDA_POC.DW.LIFE_UNIT_OF_EXPOSURE
    WHERE DW_CURRENT_FLAG = 'Y';
    
    IF (:v_lapse_rate > 5.0) THEN
      SELECT SNOWFLAKE.CORTEX.COMPLETE('mistral-large2',
        'Gera um alerta em português de Portugal: a taxa de cancelamento do portfolio é ' || 
        ROUND(:v_lapse_rate, 2) || '%, acima do limiar de 5%. ' ||
        'Sugere causas possíveis e ações corretivas para retenção de clientes.'
      ) INTO :v_alert_msg;
      
      INSERT INTO CAVIDA_POC.ORCHESTRATION.DQ_ALERTS (ALERT_TYPE, ALERT_MSG, RECORD_COUNT, CREATED_AT)
      VALUES ('PERSISTENCY_ALERT', :v_alert_msg, :v_lapse_rate, CURRENT_TIMESTAMP());
    END IF;
  END;

-- 4. Pipeline Failure Alert
CREATE OR REPLACE ALERT PIPELINE_FAILURE_ALERT
  WAREHOUSE = COMPUTE_WH
  SCHEDULE = 'USING CRON 0 8 * * * Europe/Lisbon'
  IF (EXISTS (
    SELECT 1 FROM SNOWFLAKE.ACCOUNT_USAGE.TASK_HISTORY
    WHERE STATE = 'FAILED'
      AND DATABASE_NAME = 'CAVIDA_POC'
      AND COMPLETED_TIME > DATEADD(HOUR, -24, CURRENT_TIMESTAMP())
  ))
  THEN
    CALL SYSTEM$SEND_EMAIL(
      'poc_notifications',
      'team@cavida.pt',
      'ALERTA: Falha no Pipeline CAVIDA_POC',
      'Foram detetadas falhas em tarefas nas últimas 24 horas. Verificar TASK_HISTORY.'
    );

-- 5. Alerts log table
CREATE TABLE IF NOT EXISTS CAVIDA_POC.ORCHESTRATION.DQ_ALERTS (
  ALERT_ID INTEGER AUTOINCREMENT,
  ALERT_TYPE STRING,
  ALERT_MSG STRING,
  RECORD_COUNT FLOAT,
  CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- Resume tasks
ALTER TASK DQ_PREMIUM_ANOMALY RESUME;
ALTER TASK DQ_PERSISTENCY_ALERT RESUME;
ALTER TASK DQ_CHECK_ROOT RESUME;
