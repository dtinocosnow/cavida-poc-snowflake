-- =============================================================================
-- CA Vida POC - Semantic View Deployment
-- =============================================================================
-- Deploys the INSURANCE_INTELLIGENCE semantic view from YAML specification.
-- The YAML file defines 5 tables, 7 metrics, 2 relationships, and 5 VQRs.
-- =============================================================================

USE SCHEMA CAVIDA_POC.ANALYTICS;

-- Deploy semantic view from YAML (reads from stage or inline)
-- Option 1: From stage
-- PUT file://INSURANCE_INTELLIGENCE_semantic_model.yaml @CAVIDA_POC.ANALYTICS.SEMANTIC_STAGE;
-- SELECT SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML(
--   'CAVIDA_POC.ANALYTICS.INSURANCE_INTELLIGENCE',
--   '@CAVIDA_POC.ANALYTICS.SEMANTIC_STAGE/INSURANCE_INTELLIGENCE_semantic_model.yaml'
-- );

-- Option 2: Inline (used in this POC)
SELECT SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML(
  'CAVIDA_POC.ANALYTICS.INSURANCE_INTELLIGENCE',
  $$
  -- See INSURANCE_INTELLIGENCE_semantic_model.yaml for full specification
  -- Contains:
  --   Tables: LIFE_UNIT_OF_EXPOSURE, LIFE_POLICY_TRANS, INSURANCE_PRODUCT, 
  --           INSURANCE_COVERAGE, INSURANCE_POLICY
  --   Metrics: total_premium, policy_count, avg_premium, active_policies,
  --            lapse_rate, total_sum_assured, avg_policy_duration
  --   Relationships: UOE->POLICY, UOE->PRODUCT
  --   VQRs: 5 verified query representations for validation
  $$
);

-- Verify deployment
DESCRIBE SEMANTIC VIEW CAVIDA_POC.ANALYTICS.INSURANCE_INTELLIGENCE;
