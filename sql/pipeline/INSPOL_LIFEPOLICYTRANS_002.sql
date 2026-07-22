CREATE OR REPLACE TRANSIENT TABLE CAVIDA_POC.STAGING.INSPOL_LIFEPOLICYTRANS_002 AS
WITH reci0x_extract AS (
    SELECT
        LPAD(CAST("RXNANO" AS VARCHAR), 2, '0') || LPAD(CAST("RXNMES" AS VARCHAR), 2, '0') || LPAD(CAST("RXNSEQ" AS VARCHAR), 5, '0') AS POLICY_TRANS_ID,
        "RXVALOR" AS EMPLOYEE
    FROM CAVIDA_POC.EXTRACTION.DB2_RECI0X_POC
    WHERE "RX$VAL" = 881
      AND LENGTH("RXVALOR") = 8
      AND TRIM("RXVALOR") NOT IN ('00000000', '99999999')
),

main_with_employee_id AS (
    SELECT
        lpt.POLICY_TRANS_ID,
        lpt.POLICY_NO,
        lpt.PROPOSAL_NO,
        lpt.ORIGINAL_POLICY_TRANS_ID,
        lpt.X_MOV_DT,
        lpt.TRANS_DT,
        lpt.X_VALUE_DT,
        lpt.X_EMISSION_DT,
        lpt.X_CREATION_DT,
        lpt.X_PROCESSED_DT,
        lpt.X_PERIOD_FROM_DT,
        lpt.X_PERIOD_TO_DT,
        lpt.X_CANCEL_DT,
        lpt.X_EXIT_DT,
        lpt.X_RETURNED_DT,
        lpt.TRANS_SUB_TYPE_CD,
        lpt.X_TRANS_STATUS_CD,
        lpt.X_CANCEL_REASON_CD,
        lpt.X_TRANS_PREVIOUS_STATUS_CD,
        lpt.TRANS_GROSS_AMT,
        lpt.TRANS_NET_AMT,
        lpt.X_TRANS_PURE_AMT,
        lpt.X_INEM_AMT,
        lpt.PAYMENT_METHOD_CD,
        lpt.X_SUBS_CHARGE_AMT,
        lpt.X_SUBS_FEE_AMT,
        lpt.X_MANAGEMENT_FEE_AMT,
        lpt.X_REINVESTMENT_FLG,
        lpt.X_RET_REASON_CD,
        lpt.X_IS_CLOSED_FLG,
        rx.EMPLOYEE AS EMPLOYEE_ID,
        lpt.AGENCY_INT_ID,
        lpt.X_CHARGEBACK_FLG,
        lpt.X_RESULT_PARTICIPATION_FLG
    FROM reci0x_extract rx
    RIGHT JOIN CAVIDA_POC.STAGING.INSPOL_LIFEPOLICYTRANS_001 lpt
        ON rx.POLICY_TRANS_ID = lpt.POLICY_TRANS_ID
       AND lpt.TRANS_SUB_TYPE_CD = '5'
),

entvin_extract AS (
    SELECT
        SUBSTR("EVVALO", 1, 8) AS X_EMPLOYEE_EXT_ID,
        "EV_REL"
    FROM CAVIDA_POC.EXTRACTION.DB2_ENTVIN_POC
    WHERE "EV_INF" = 900
),

entrel_extract AS (
    SELECT
        "ER_REL",
        "ER_COD"
    FROM CAVIDA_POC.EXTRACTION.DB2_ENTREL_POC
    WHERE "ERSTEN" = 'F'
      AND "ERTENT" = 'B'
      AND "ERTIPO" = 'ENT'
),

entvin_entrel_join AS (
    SELECT
        ev.X_EMPLOYEE_EXT_ID,
        TRIM(CAST(er."ER_COD" AS VARCHAR)) AS ER_COD
    FROM entvin_extract ev
    INNER JOIN entrel_extract er
        ON ev."EV_REL" = er."ER_REL"
),

apolpa_employee AS (
    SELECT
        ap."AL$MOD",
        ap."ALNAPO",
        ap."ALDTIN",
        COALESCE(ee.X_EMPLOYEE_EXT_ID, '') AS X_EMPLOYEE_EXT_ID
    FROM CAVIDA_POC.EXTRACTION.DB2_APOLPA_POC ap
    LEFT JOIN entvin_entrel_join ee
        ON TRIM(CAST(ap."AL$ENT" AS VARCHAR)) = ee.ER_COD
       AND ap."AL$PAP" = 'FUN'
    WHERE ap."AL$PAP" = 'FUN'
),

apolpa_dedup AS (
    SELECT
        "AL$MOD",
        "ALNAPO",
        X_EMPLOYEE_EXT_ID
    FROM (
        SELECT
            "AL$MOD",
            "ALNAPO",
            "ALDTIN",
            X_EMPLOYEE_EXT_ID,
            ROW_NUMBER() OVER(PARTITION BY "AL$MOD", "ALNAPO" ORDER BY "ALDTIN" DESC) AS rn
        FROM apolpa_employee
    )
    WHERE rn = 1
),

with_employee AS (
    SELECT
        m.POLICY_TRANS_ID,
        m.POLICY_NO,
        m.ORIGINAL_POLICY_TRANS_ID,
        m.X_MOV_DT,
        m.TRANS_DT,
        m.X_VALUE_DT,
        m.X_EMISSION_DT,
        m.X_CREATION_DT,
        m.X_PROCESSED_DT,
        m.X_PERIOD_FROM_DT,
        m.X_PERIOD_TO_DT,
        m.X_CANCEL_DT,
        m.X_EXIT_DT,
        m.X_RETURNED_DT,
        m.TRANS_SUB_TYPE_CD,
        m.X_TRANS_STATUS_CD,
        m.X_CANCEL_REASON_CD,
        m.X_TRANS_PREVIOUS_STATUS_CD,
        m.TRANS_GROSS_AMT,
        m.TRANS_NET_AMT,
        m.X_TRANS_PURE_AMT,
        m.X_INEM_AMT,
        m.PAYMENT_METHOD_CD,
        m.X_SUBS_CHARGE_AMT,
        m.X_SUBS_FEE_AMT,
        m.X_MANAGEMENT_FEE_AMT,
        m.X_REINVESTMENT_FLG,
        m.X_RET_REASON_CD,
        m.X_IS_CLOSED_FLG,
        CASE
            WHEN NULLIF(TRIM(m.EMPLOYEE_ID), '') IS NULL THEN ad.X_EMPLOYEE_EXT_ID
            ELSE m.EMPLOYEE_ID
        END AS X_EMPLOYEE_EXT_ID,
        m.AGENCY_INT_ID,
        m.X_CHARGEBACK_FLG,
        m.X_RESULT_PARTICIPATION_FLG
    FROM main_with_employee_id m
    LEFT JOIN apolpa_dedup ad
        ON m.PROPOSAL_NO = LPAD(CAST(ad."AL$MOD" AS VARCHAR), 2, '0') || LPAD(CAST(ad."ALNAPO" AS VARCHAR), 8, '0')
),

with_processed_flg AS (
    SELECT
        POLICY_TRANS_ID,
        POLICY_NO,
        ORIGINAL_POLICY_TRANS_ID,
        X_MOV_DT,
        TRANS_DT,
        X_VALUE_DT,
        X_EMISSION_DT,
        X_CREATION_DT,
        X_PROCESSED_DT,
        X_PERIOD_FROM_DT,
        X_PERIOD_TO_DT,
        X_CANCEL_DT,
        X_EXIT_DT,
        X_RETURNED_DT,
        TRANS_SUB_TYPE_CD,
        X_TRANS_STATUS_CD,
        X_CANCEL_REASON_CD,
        X_TRANS_PREVIOUS_STATUS_CD,
        TRANS_GROSS_AMT,
        TRANS_NET_AMT,
        X_TRANS_PURE_AMT,
        X_INEM_AMT,
        PAYMENT_METHOD_CD,
        X_SUBS_CHARGE_AMT,
        X_SUBS_FEE_AMT,
        X_MANAGEMENT_FEE_AMT,
        X_REINVESTMENT_FLG,
        X_RET_REASON_CD,
        X_IS_CLOSED_FLG,
        X_EMPLOYEE_EXT_ID,
        AGENCY_INT_ID,
        X_CHARGEBACK_FLG,
        X_RESULT_PARTICIPATION_FLG,
        CASE
            WHEN X_PROCESSED_DT IS NOT NULL
             AND COALESCE(
                   SUM(CASE WHEN X_PROCESSED_DT IS NOT NULL THEN 1 ELSE 0 END)
                       OVER(PARTITION BY POLICY_TRANS_ID
                            ORDER BY X_TRANS_STATUS_CD, X_MOV_DT
                            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING),
                   0) = 0
            THEN '1'
            ELSE '0'
        END AS X_PROCESSED_FLG
    FROM with_employee
),

recpro_extract AS (
    SELECT DISTINCT
        LPAD(CAST("RPNREC" AS VARCHAR), 9, '0') AS POLICY_TRANS_ID
    FROM CAVIDA_POC.EXTRACTION.DB2_RECPRO_POC
    WHERE "RPSITU" = 5
)

SELECT
    pf.POLICY_TRANS_ID,
    pf.POLICY_NO,
    pf.ORIGINAL_POLICY_TRANS_ID,
    pf.X_MOV_DT,
    pf.TRANS_DT,
    pf.X_VALUE_DT,
    pf.X_EMISSION_DT,
    pf.X_CREATION_DT,
    pf.X_PROCESSED_DT,
    pf.X_PERIOD_FROM_DT,
    pf.X_PERIOD_TO_DT,
    pf.X_CANCEL_DT,
    pf.X_EXIT_DT,
    pf.X_RETURNED_DT,
    pf.TRANS_SUB_TYPE_CD,
    pf.X_TRANS_STATUS_CD,
    pf.X_CANCEL_REASON_CD,
    pf.X_TRANS_PREVIOUS_STATUS_CD,
    pf.TRANS_GROSS_AMT,
    pf.TRANS_NET_AMT,
    pf.X_TRANS_PURE_AMT,
    pf.X_INEM_AMT,
    pf.PAYMENT_METHOD_CD,
    pf.X_SUBS_CHARGE_AMT,
    pf.X_SUBS_FEE_AMT,
    pf.X_MANAGEMENT_FEE_AMT,
    pf.X_REINVESTMENT_FLG,
    pf.X_RET_REASON_CD,
    pf.X_IS_CLOSED_FLG,
    pf.X_EMPLOYEE_EXT_ID,
    pf.AGENCY_INT_ID,
    pf.X_PROCESSED_FLG,
    pf.X_CHARGEBACK_FLG,
    pf.X_RESULT_PARTICIPATION_FLG,
    CASE WHEN rp.POLICY_TRANS_ID IS NOT NULL THEN '1' ELSE '0' END AS X_POLICY_TRANS_MANUAL_FLG
FROM with_processed_flg pf
LEFT JOIN recpro_extract rp
    ON pf.POLICY_TRANS_ID = rp.POLICY_TRANS_ID
;
