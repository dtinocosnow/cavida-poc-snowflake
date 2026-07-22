-- =============================================================================
-- CA Vida POC - Tag-Based Dynamic Data Masking (PII Protection)
-- =============================================================================
-- Implements tag-based masking for GDPR compliance.
-- Any column tagged with PII_TYPE will be automatically masked for non-admin roles.
-- =============================================================================

USE SCHEMA CAVIDA_POC.ANALYTICS;

-- 1. Create PII classification tag
CREATE OR REPLACE TAG PII_TYPE
  ALLOWED_VALUES 'NAME', 'EMAIL', 'PHONE', 'NIF', 'ADDRESS'
  COMMENT = 'Classifies columns containing personally identifiable information';

-- 2. Create masking policy for string PII columns
CREATE OR REPLACE MASKING POLICY PII_MASK_STRING AS (val STRING)
  RETURNS STRING ->
    CASE
      WHEN CURRENT_ROLE() IN ('ACCOUNTADMIN', 'DATA_ENGINEER')
        THEN val
      ELSE '***MASKED***'
    END
  COMMENT = 'Masks PII string columns for non-privileged roles';

-- 3. Attach masking policy to the PII_TYPE tag
ALTER TAG PII_TYPE SET MASKING POLICY PII_MASK_STRING;

-- 4. Apply tag to PII columns (example)
-- ALTER TABLE CAVIDA_POC.DW.LIFE_POLICY_TRANS 
--   ALTER COLUMN POLICY_HOLDER_NAME SET TAG CAVIDA_POC.ANALYTICS.PII_TYPE = 'NAME';

-- Verification:
-- SELECT * FROM TABLE(INFORMATION_SCHEMA.POLICY_REFERENCES(
--   REF_ENTITY_NAME => 'CAVIDA_POC.ANALYTICS.PII_TYPE',
--   REF_ENTITY_DOMAIN => 'TAG'
-- ));
