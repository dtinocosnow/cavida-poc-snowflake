# POC Change Log — UOE SCD2 Primary Key Deduplication

## Date: 2026-07-22

## Context

During the execution of the SAS job `_05_02_030_Load_LifeUnitOfExposure`, 3 records are rejected by the SCD Type 2 process because they violate the integrity constraint `PRIM_KEY`. This behaviour was communicated by CA Vida to all PoC participants for transparency and consistency.

The SAS warning message:
```
WARNING: Add/Update failed for data set POC.LIFE_UNIT_OF_EXPOSURE because data value(s) 
do not comply with integrity constraint PRIM_KEY, 3 observations rejected.
```

## Affected Records

| POLICY_RK | X_POLICY_PROPOSAL_RK | X_ORDER_CD | COVERAGE_RIDER_RK | X_POLICY_VERSION |
|-----------|---------------------|------------|-------------------|-----------------|
| 70128863472 | 848495276043 | 3 | 382355762304 | 1 |
| 70128863472 | 848495276043 | 3 | 382355762304 | 2 |
| 70128863472 | 848495276043 | 3 | 382355762304 | 3 |

## Root Cause

The source data contains exact duplicates on the SCD2 natural key composite:
`(POLICY_RK, X_POLICY_PROPOSAL_RK, X_ORDER_CD, COVERAGE_RIDER_RK, X_POLICY_VERSION)`

Each of the 3 versions above appears twice in the source staging table (`INSPOL_LIFEUNITOFEXPOSURE_005`). SAS rejects the duplicate insertion attempt; Snowflake's initial CTAS loaded all records without constraint enforcement.

## Action Taken

Applied deduplication using a window function to replicate SAS's PK constraint rejection:

```sql
CREATE OR REPLACE TABLE CAVIDA_POC.DW.LIFE_UNIT_OF_EXPOSURE AS
SELECT * FROM (
  SELECT *,
    ROW_NUMBER() OVER(
      PARTITION BY POLICY_RK, X_POLICY_PROPOSAL_RK, X_ORDER_CD, COVERAGE_RIDER_RK, X_POLICY_VERSION
      ORDER BY CHANGE_EFFECTIVE_FROM_DTTM DESC
    ) AS _rn
  FROM CAVIDA_POC.DW.LIFE_UNIT_OF_EXPOSURE
)
WHERE _rn = 1;

ALTER TABLE CAVIDA_POC.DW.LIFE_UNIT_OF_EXPOSURE DROP COLUMN _RN;
```

## Result

| Metric | Before | After |
|--------|--------|-------|
| Row count | 24,168,838 | **24,168,835** |
| Duplicate PK combinations | 3 | 0 |
| Match vs SAS | +3 records | **Exact match** |

## Impact Assessment

- Records affected: 3 / 24,168,838 = **0.0000124%**
- CA Vida confirmed these "may be safely disregarded" for PoC reconciliation
- No impact on any metrics, aggregations, or business logic
- Deduplication applied for byte-level parity with SAS reference

## Production Recommendation

In a production implementation, add the deduplication as a standard step in the UOE pipeline (before or during the SCD2 merge), using the same `ROW_NUMBER()` pattern. This is equivalent to SAS's integrity constraint behaviour but explicit and auditable.
