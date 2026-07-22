--------------------------------------------------------------------
-- Transformation: _04_02_060_LifePolicyTrans_001
-- Target: CAVIDA_POC.STAGING.INSPOL_LIFEPOLICYTRANS_001
-- Sources: DB2_RECIBO_POC, DB2_MOPEC1_POC, DB2_MOVIML_POC,
--          DB2_EVENTO_POC, DB2_APOL00_POC
-- DW anti-join: CAVIDA_POC.DW.X_LIFE_POLICY_TRANS_HIST (empty)
-- Expected rows: 149,714,421
--------------------------------------------------------------------

CREATE OR REPLACE TRANSIENT TABLE CAVIDA_POC.STAGING.INSPOL_LIFEPOLICYTRANS_001 AS
WITH
--------------------------------------------------------------------
-- Step 1: Extract MOPEC1 (financial details from event type 05)
--------------------------------------------------------------------
extract_mopec1 AS (
    SELECT
        CASE
            WHEN LPAD(EDCMOD::VARCHAR,2,'0') IN ('05','06','07','08','09','10','11','12')
                THEN EDVL16 / 100.0
            WHEN LPAD(EDCMOD::VARCHAR,2,'0') NOT IN ('05','06','07','08','09','10','11','12')
                AND EDVL07 != 0
                THEN (EDVL01 - EDVL07) / 100.0
            ELSE 0
        END AS X_SUBS_CHARGE_AMT,
        EDVL16 / 100.0 AS X_SUBS_FEE_AMT,
        EDVL17 / 100.0 AS X_MANAGEMENT_FEE_AMT,
        EDNANO,
        EDNMES,
        EDNSEQ
    FROM CAVIDA_POC.EXTRACTION.DB2_MOPEC1_POC
    WHERE EDCEVE = '05'
),

--------------------------------------------------------------------
-- Step 2: Extract RECIBO (main receipt/transaction extract)
--------------------------------------------------------------------
extract_recibo AS (
    SELECT
        LPAD(RCNANO::VARCHAR,2,'0') || LPAD(RCNMES::VARCHAR,2,'0') || LPAD(RCNSEQ::VARCHAR,5,'0') AS POLICY_TRANS_ID,
        LPAD("RC$MOD"::VARCHAR,2,'0') || LPAD("RC$APL"::VARCHAR,8,'0') AS POLICY_NO,
        LPAD("RC$MOD"::VARCHAR,2,'0') || LPAD(RCNAPO::VARCHAR,8,'0') AS PROPOSAL_NO,
        TRY_TO_DATE(LPAD(RCACOB::VARCHAR,4,'0') || LPAD(RCMCOB::VARCHAR,2,'0') || LPAD(RCDCOB::VARCHAR,2,'0'), 'YYYYMMDD') AS TRANS_DT,
        TRY_TO_DATE(LPAD(RCAFR2::VARCHAR,4,'0') || LPAD(RCMFR2::VARCHAR,2,'0') || LPAD(RCDFR2::VARCHAR,2,'0'), 'YYYYMMDD') AS X_VALUE_DT,
        TRY_TO_DATE(LPAD(RCAEMI::VARCHAR,4,'0') || LPAD(RCMEMI::VARCHAR,2,'0') || LPAD(RCDEMI::VARCHAR,2,'0'), 'YYYYMMDD') AS X_EMISSION_DT,
        TRY_TO_DATE(LPAD(RCACRI::VARCHAR,4,'0') || LPAD(RCMCRI::VARCHAR,2,'0') || LPAD(RCDCRI::VARCHAR,2,'0'), 'YYYYMMDD') AS X_CREATION_DT,
        TRY_TO_DATE(LPAD(RCADEV::VARCHAR,4,'0') || LPAD(RCMDEV::VARCHAR,2,'0') || LPAD(RCDDEV::VARCHAR,2,'0'), 'YYYYMMDD') AS X_PROCESSED_DT,
        TRY_TO_DATE(LPAD(RCAPDE::VARCHAR,4,'0') || LPAD(RCMPDE::VARCHAR,2,'0') || LPAD(RCDPDE::VARCHAR,2,'0'), 'YYYYMMDD') AS X_PERIOD_FROM_DT,
        TRY_TO_DATE(LPAD(RCAPDA::VARCHAR,4,'0') || LPAD(RCMPDA::VARCHAR,2,'0') || LPAD(RCDPDA::VARCHAR,2,'0'), 'YYYYMMDD') AS X_PERIOD_TO_DT,
        RCESPC AS TRANS_SUB_TYPE_CD,
        RCSITU AS X_TRANS_STATUS_CD,
        TRY_TO_DATE(LPAD(RCAANU::VARCHAR,4,'0') || LPAD(RCMANU::VARCHAR,2,'0') || LPAD(RCDANU::VARCHAR,2,'0'), 'YYYYMMDD') AS X_CANCEL_DT,
        RCRANU AS X_CANCEL_REASON_CD,
        RCSTAN AS X_TRANS_PREVIOUS_STATUS_CD,
        RCPRTO / 100.0 AS TRANS_GROSS_AMT,
        CASE
            WHEN RCSTA3 = 'K' AND RCESPC = 9 THEN (RCPRSR / 100.0) + (RCENV2 / 100.0)
            ELSE RCPRSR / 100.0
        END AS TRANS_NET_AMT,
        CASE
            WHEN LPAD("RC$MOD"::VARCHAR,2,'0') NOT IN ('05','06','07','08','09','10','11','12')
                THEN RCVAL2 / 100.0
            ELSE RCPRTO / 100.0
        END AS X_TRANS_PURE_AMT,
        RCENP1 / 100.0 AS X_INEM_AMT,
        RCTCOB AS PAYMENT_METHOD_CD,
        TRY_TO_DATE(LPAD(RCAUST::VARCHAR,4,'0') || LPAD(RCMUST::VARCHAR,2,'0') || LPAD(RCDUST::VARCHAR,2,'0'), 'YYYYMMDD') AS MOV_DT,
        RCNANO,
        RCNMES,
        RCNSEQ,
        TRY_TO_DATE(LPAD(RCADVL::VARCHAR,4,'0') || LPAD(RCMDVL::VARCHAR,2,'0') || LPAD(RCDDVL::VARCHAR,2,'0'), 'YYYYMMDD') AS X_RETURNED_DT,
        CASE WHEN RCSTA3 = 'H' THEN 1 ELSE 0 END AS X_REINVESTMENT_FLG,
        "RC$AG2",
        "RC$TC1",
        RCSTA3 AS X_CHARGEBACK_CD,
        CASE WHEN RCSTA9 = 24 THEN '1' ELSE '0' END AS X_RESULT_PARTICIPATION_FLG
    FROM CAVIDA_POC.EXTRACTION.DB2_RECIBO_POC
    WHERE NOT (RCSTA3 = 'F' AND RCESPC IN (5, 9))
),

--------------------------------------------------------------------
-- Step 3: DISTINCT from DW (anti-join source, table is empty)
--------------------------------------------------------------------
dw_existing AS (
    SELECT DISTINCT POLICY_TRANS_ID
    FROM CAVIDA_POC.DW.X_LIFE_POLICY_TRANS_HIST
),

--------------------------------------------------------------------
-- Step 4: Anti-join (remove already-loaded closed receipts)
--------------------------------------------------------------------
extract_recibo2 AS (
    SELECT r.*
    FROM extract_recibo r
    LEFT JOIN dw_existing d ON r.POLICY_TRANS_ID = d.POLICY_TRANS_ID
    WHERE d.POLICY_TRANS_ID IS NULL
),

--------------------------------------------------------------------
-- Step 5: Flag estornos (chargebacks with code 'A')
--------------------------------------------------------------------
chargeback_rec AS (
    SELECT POLICY_TRANS_ID, X_CHARGEBACK_CD, X_RESULT_PARTICIPATION_FLG
    FROM extract_recibo2
    WHERE X_CHARGEBACK_CD = 'A'
),

--------------------------------------------------------------------
-- Step 6: Participation flag (trans_sub_type = 9)
--------------------------------------------------------------------
participation_flag AS (
    SELECT POLICY_TRANS_ID, POLICY_NO, X_RESULT_PARTICIPATION_FLG
    FROM extract_recibo2
    WHERE TRANS_SUB_TYPE_CD = 9
),

--------------------------------------------------------------------
-- Step 7: RIGHT JOIN MOPEC1 to get financial details → INFO_RECIBOS
--------------------------------------------------------------------
info_recibos AS (
    SELECT
        r.POLICY_TRANS_ID,
        r.POLICY_NO,
        r.PROPOSAL_NO,
        '' AS ORIGINAL_POLICY_TRANS_ID,
        r.TRANS_DT,
        r.X_VALUE_DT,
        r.X_EMISSION_DT,
        r.X_CREATION_DT,
        r.X_PROCESSED_DT,
        r.X_PERIOD_FROM_DT,
        r.X_PERIOD_TO_DT,
        r.TRANS_SUB_TYPE_CD,
        r.X_TRANS_STATUS_CD,
        r.X_CANCEL_DT,
        r.X_CANCEL_REASON_CD,
        r.X_TRANS_PREVIOUS_STATUS_CD,
        r.TRANS_GROSS_AMT,
        r.TRANS_NET_AMT,
        r.X_TRANS_PURE_AMT,
        r.X_INEM_AMT,
        r.PAYMENT_METHOD_CD,
        r.MOV_DT,
        r.RCNANO,
        r.RCNMES,
        r.RCNSEQ,
        r.X_RETURNED_DT,
        r.X_REINVESTMENT_FLG,
        COALESCE(m.X_SUBS_CHARGE_AMT, 0) AS X_SUBS_CHARGE_AMT,
        COALESCE(m.X_SUBS_FEE_AMT, 0) AS X_SUBS_FEE_AMT,
        COALESCE(m.X_MANAGEMENT_FEE_AMT, 0) AS X_MANAGEMENT_FEE_AMT,
        CASE WHEN r.X_TRANS_STATUS_CD IN (5, 9) THEN 'Y' ELSE 'N' END AS X_IS_CLOSED_FLG,
        CASE
            WHEN TRIM(r."RC$AG2"::VARCHAR) = '.' THEN ''
            ELSE TRIM(r."RC$AG2"::VARCHAR)
        END AS AGENCY_INT_ID
    FROM extract_recibo2 r
    LEFT JOIN extract_mopec1 m
        ON r.RCNANO = m.EDNANO
        AND r.RCNMES = m.EDNMES
        AND r.RCNSEQ = m.EDNSEQ
),

--------------------------------------------------------------------
-- Step 8: Extract Eventos (document types R and E)
--------------------------------------------------------------------
info_eventos AS (
    SELECT
        EOREFD AS POLICY_TRANS_ID,
        TRY_TO_DATE(LPAD(EODEVE::VARCHAR, 8, '0'), 'YYYYMMDD') AS EVENT_DT,
        "EO$EVE" AS EVENT_STATUS_CD,
        EOSTSO AS X_CHARGEBACK_CD,
        EOTDOC AS DOC_TYPE
    FROM CAVIDA_POC.EXTRACTION.DB2_EVENTO_POC
    WHERE EOTDOC IN ('R', 'E')
),

--------------------------------------------------------------------
-- Step 9: Extract Movimentos (document type != E)
--------------------------------------------------------------------
info_movimentos AS (
    SELECT
        LPAD(MLNANO::VARCHAR,2,'0') || LPAD(MLNMES::VARCHAR,2,'0') || LPAD(MLNSEQ::VARCHAR,5,'0') AS POLICY_TRANS_ID,
        MLSITC AS X_TRANS_STATUS_CD,
        TRY_TO_DATE(LPAD(MLASAI::VARCHAR,4,'0') || LPAD(MLMSAI::VARCHAR,2,'0') || LPAD(MLDSAI::VARCHAR,2,'0'), 'YYYYMMDD') AS X_SITU_EXIT_DT,
        TRY_TO_DATE(LPAD(MLAENT::VARCHAR,4,'0') || LPAD(MLMENT::VARCHAR,2,'0') || LPAD(MLDENT::VARCHAR,2,'0'), 'YYYYMMDD') AS X_SITU_ENTRY_DT,
        MLSITC AS X_RET_REASON_CD
    FROM CAVIDA_POC.EXTRACTION.DB2_MOVIML_POC
    WHERE MLTDOC != 'E'
),

--------------------------------------------------------------------
-- Step 10: ROW EXPLOSION - Create Historical Observations
-- Produces multiple status observations per transaction
--------------------------------------------------------------------

-- 10a: RECIBOS explosion (1-6 rows per receipt based on lifecycle)
recibos_status0 AS (
    SELECT POLICY_TRANS_ID, 0 AS STATUS_CD, X_CREATION_DT AS MOV_DT, 'RECIBO' AS SOURCE, NULL AS X_RET_REASON_CD, 0 AS "ORDER"
    FROM info_recibos
    WHERE X_TRANS_STATUS_CD >= 0
),
recibos_status1 AS (
    SELECT POLICY_TRANS_ID, 1 AS STATUS_CD, X_EMISSION_DT AS MOV_DT, 'RECIBO' AS SOURCE, NULL AS X_RET_REASON_CD, 1 AS "ORDER"
    FROM info_recibos
    WHERE X_TRANS_STATUS_CD >= 1
      AND NOT (X_TRANS_STATUS_CD = 5 AND X_TRANS_PREVIOUS_STATUS_CD < 1)
      AND NOT (X_TRANS_STATUS_CD = 9 AND X_TRANS_PREVIOUS_STATUS_CD < 1)
),
recibos_status2 AS (
    SELECT POLICY_TRANS_ID, 2 AS STATUS_CD, X_PROCESSED_DT AS MOV_DT, 'RECIBO' AS SOURCE, NULL AS X_RET_REASON_CD, 100 AS "ORDER"
    FROM info_recibos
    WHERE X_TRANS_STATUS_CD >= 2
      AND NOT (X_TRANS_STATUS_CD = 5 AND X_TRANS_PREVIOUS_STATUS_CD < 2)
      AND NOT (X_TRANS_STATUS_CD = 9 AND X_TRANS_PREVIOUS_STATUS_CD < 2)
),
recibos_status3 AS (
    SELECT POLICY_TRANS_ID, 3 AS STATUS_CD, MOV_DT AS MOV_DT, 'RECIBO' AS SOURCE, NULL AS X_RET_REASON_CD, 300 AS "ORDER"
    FROM info_recibos
    WHERE X_TRANS_STATUS_CD = 3 AND X_TRANS_PREVIOUS_STATUS_CD = 1
),
recibos_status5 AS (
    SELECT POLICY_TRANS_ID, 5 AS STATUS_CD, TRANS_DT AS MOV_DT, 'RECIBO' AS SOURCE, NULL AS X_RET_REASON_CD, 500 AS "ORDER"
    FROM info_recibos
    WHERE X_TRANS_STATUS_CD = 5
),
recibos_status9 AS (
    SELECT POLICY_TRANS_ID, 9 AS STATUS_CD, X_CANCEL_DT AS MOV_DT, 'RECIBO' AS SOURCE, NULL AS X_RET_REASON_CD, 900 AS "ORDER"
    FROM info_recibos
    WHERE X_TRANS_STATUS_CD = 9
),

recibos_all AS (
    SELECT * FROM recibos_status0
    UNION ALL SELECT * FROM recibos_status1
    UNION ALL SELECT * FROM recibos_status2
    UNION ALL SELECT * FROM recibos_status3
    UNION ALL SELECT * FROM recibos_status5
    UNION ALL SELECT * FROM recibos_status9
),

-- 10b: Extra status 2 for receipts at status 1 that have event 02
policy_trans_status1 AS (
    SELECT DISTINCT POLICY_TRANS_ID
    FROM info_recibos
    WHERE X_TRANS_STATUS_CD = 1
),
recibos_novo_status2 AS (
    SELECT
        e.POLICY_TRANS_ID,
        2 AS STATUS_CD,
        e.EVENT_DT AS MOV_DT,
        'RECIBO' AS SOURCE,
        NULL AS X_RET_REASON_CD,
        100 AS "ORDER"
    FROM policy_trans_status1 p
    INNER JOIN info_eventos e
        ON p.POLICY_TRANS_ID = e.POLICY_TRANS_ID
        AND e.EVENT_STATUS_CD = '02'
),

recibos_combined AS (
    SELECT * FROM recibos_all
    UNION ALL
    SELECT * FROM recibos_novo_status2
),

-- 10c: EVENTOS explosion (event status 30→0, 33→9, 02→2)
eventos_exploded AS (
    SELECT
        POLICY_TRANS_ID,
        CASE
            WHEN EVENT_STATUS_CD = '30' THEN 0
            WHEN EVENT_STATUS_CD = '33' THEN 9
            WHEN EVENT_STATUS_CD = '02' THEN 2
        END AS STATUS_CD,
        EVENT_DT AS MOV_DT,
        'EVENTO' AS SOURCE,
        CAST(NULL AS VARCHAR(4)) AS X_RET_REASON_CD,
        CASE
            WHEN EVENT_STATUS_CD = '30' THEN 0
            WHEN EVENT_STATUS_CD = '33' THEN 900
            WHEN EVENT_STATUS_CD = '02' THEN 200
        END AS "ORDER"
    FROM info_eventos
    WHERE EVENT_STATUS_CD IN ('30', '33', '02')
),

-- 10d: Merge RECIBOS LEFT JOIN EVENTOS (coalesce to prefer event data)
recibos_eventos_merged AS (
    SELECT
        COALESCE(b.POLICY_TRANS_ID, a.POLICY_TRANS_ID) AS POLICY_TRANS_ID,
        COALESCE(b.STATUS_CD, a.STATUS_CD) AS STATUS_CD,
        COALESCE(b.MOV_DT, a.MOV_DT) AS MOV_DT,
        COALESCE(b.SOURCE, a.SOURCE) AS SOURCE,
        COALESCE(b.X_RET_REASON_CD, a.X_RET_REASON_CD) AS X_RET_REASON_CD,
        COALESCE(b."ORDER", a."ORDER") AS "ORDER"
    FROM recibos_combined a
    LEFT JOIN eventos_exploded b
        ON a.POLICY_TRANS_ID = b.POLICY_TRANS_ID
        AND a.STATUS_CD = b.STATUS_CD
),

-- 10e: MOVIMENTOS explosion (status transitions)
movimentos_raw AS (
    -- Row for STATUS_CD=2 (exit from situation) when X_SITU_EXIT_DT is not null
    SELECT
        POLICY_TRANS_ID, 2 AS STATUS_CD, X_SITU_EXIT_DT AS MOV_DT,
        'MOVIMENTOS' AS SOURCE, CAST(NULL AS VARCHAR(4)) AS X_RET_REASON_CD
    FROM info_movimentos
    WHERE X_SITU_EXIT_DT IS NOT NULL

    UNION ALL

    -- Row for STATUS_CD=3 (returned) when X_TRANS_STATUS_CD != '0000'
    SELECT
        POLICY_TRANS_ID, 3 AS STATUS_CD, X_SITU_ENTRY_DT AS MOV_DT,
        'MOVIMENTOS' AS SOURCE, X_TRANS_STATUS_CD::VARCHAR(4) AS X_RET_REASON_CD
    FROM info_movimentos
    WHERE X_TRANS_STATUS_CD != '0000'
),

movimentos_ordered AS (
    SELECT
        POLICY_TRANS_ID,
        STATUS_CD,
        MOV_DT,
        SOURCE,
        X_RET_REASON_CD,
        299 + ROW_NUMBER() OVER (PARTITION BY POLICY_TRANS_ID ORDER BY MOV_DT, STATUS_CD) AS "ORDER"
    FROM movimentos_raw
),

-- 10f: FINAL merge - remove STATUS_CD=2 from merged where MOVIMENTOS exist, then append
movimentos_trans_ids AS (
    SELECT DISTINCT POLICY_TRANS_ID FROM movimentos_ordered
),

historical_obs AS (
    SELECT POLICY_TRANS_ID, STATUS_CD, MOV_DT, SOURCE, X_RET_REASON_CD, "ORDER"
    FROM recibos_eventos_merged
    WHERE NOT (
        STATUS_CD = 2
        AND POLICY_TRANS_ID IN (SELECT POLICY_TRANS_ID FROM movimentos_trans_ids)
    )

    UNION ALL

    SELECT POLICY_TRANS_ID, STATUS_CD, MOV_DT, SOURCE, X_RET_REASON_CD, "ORDER"
    FROM movimentos_ordered
),

--------------------------------------------------------------------
-- Step 11: Multiply by Historical Movements (join back to receipts)
--------------------------------------------------------------------
multiplied AS (
    SELECT
        ir.POLICY_TRANS_ID,
        ir.POLICY_NO,
        ir.PROPOSAL_NO,
        ir.ORIGINAL_POLICY_TRANS_ID,
        ir.TRANS_DT,
        ir.X_VALUE_DT,
        ir.X_EMISSION_DT,
        ir.X_CREATION_DT,
        ir.X_PROCESSED_DT,
        ir.X_PERIOD_FROM_DT,
        ir.X_PERIOD_TO_DT,
        ir.TRANS_SUB_TYPE_CD,
        ir.X_TRANS_STATUS_CD,
        ir.X_CANCEL_DT,
        ir.X_CANCEL_REASON_CD,
        ir.X_TRANS_PREVIOUS_STATUS_CD,
        ir.TRANS_GROSS_AMT,
        ir.TRANS_NET_AMT,
        ir.X_TRANS_PURE_AMT,
        ir.X_INEM_AMT,
        ir.PAYMENT_METHOD_CD,
        ir.MOV_DT,
        ir.RCNANO,
        ir.RCNMES,
        ir.RCNSEQ,
        ir.X_RETURNED_DT,
        ir.X_REINVESTMENT_FLG,
        ir.X_SUBS_CHARGE_AMT,
        ir.X_SUBS_FEE_AMT,
        ir.X_MANAGEMENT_FEE_AMT,
        ir.X_IS_CLOSED_FLG,
        ir.AGENCY_INT_ID,
        ho.STATUS_CD,
        ho.MOV_DT AS NEW_MOV_DT,
        ho.X_RET_REASON_CD AS X_RET_REASON_CD_HO,
        ho."ORDER"
    FROM info_recibos ir
    INNER JOIN historical_obs ho
        ON ir.POLICY_TRANS_ID = ho.POLICY_TRANS_ID
),

--------------------------------------------------------------------
-- Step 12: Extract Prods by Policy (product ID from APOL00)
--------------------------------------------------------------------
prods_by_policy AS (
    SELECT
        LPAD("A0$MOD"::VARCHAR,2,'0') || LPAD("A0$APL"::VARCHAR,8,'0') AS POLICY_NO,
        LPAD("A0$MOD"::VARCHAR,2,'0') || LPAD(A0NVER::VARCHAR,2,'0') AS PROD_ID
    FROM CAVIDA_POC.EXTRACTION.DB2_APOL00_POC
    WHERE "A0$APL" != 0
),

--------------------------------------------------------------------
-- Step 13: Join with the Prod (add PROD_ID)
--------------------------------------------------------------------
recibos_prd AS (
    SELECT
        m.*,
        p.PROD_ID
    FROM multiplied m
    LEFT JOIN prods_by_policy p ON m.POLICY_NO = p.POLICY_NO
),

--------------------------------------------------------------------
-- Steps 14-15: Extract Eventos 02 and 03
--------------------------------------------------------------------
eventos02 AS (
    SELECT POLICY_TRANS_ID, EVENT_DT, EVENT_STATUS_CD
    FROM info_eventos
    WHERE EVENT_STATUS_CD = '02'
),
eventos03 AS (
    SELECT DISTINCT POLICY_TRANS_ID, EVENT_STATUS_CD
    FROM info_eventos
    WHERE EVENT_STATUS_CD = '03'
),

--------------------------------------------------------------------
-- Step 16: Ajusta as Datas e Marca Flags (User Written - RETAIN logic)
-- Uses window functions to replicate SAS BY-group RETAIN behavior
--------------------------------------------------------------------
adjusted AS (
    SELECT
        rp.POLICY_TRANS_ID,
        rp.POLICY_NO,
        rp.PROPOSAL_NO,
        rp.ORIGINAL_POLICY_TRANS_ID,

        -- X_MOV_DT: default is NEW_MOV_DT, adjusted if status=2 and has processed date
        CASE
            WHEN rp.STATUS_CD = 2
                AND COALESCE(e02.EVENT_DT, rp.X_CREATION_DT) IS NOT NULL
                THEN COALESCE(e02.EVENT_DT, rp.X_CREATION_DT)
            ELSE rp.NEW_MOV_DT
        END AS X_MOV_DT,

        rp.X_VALUE_DT,

        -- X_CREATION_DT: from the STATUS_CD=0 row in same POLICY_TRANS_ID (retained)
        MAX(CASE WHEN rp.STATUS_CD = 0 THEN rp.NEW_MOV_DT END)
            OVER (PARTITION BY rp.POLICY_TRANS_ID) AS X_CREATION_DT,

        -- X_EMISSION_DT: NULL for STATUS_CD=0, NEW_MOV_DT for STATUS_CD=1, retained otherwise
        CASE
            WHEN rp.STATUS_CD = 0 THEN NULL
            WHEN rp.STATUS_CD = 1 THEN rp.NEW_MOV_DT
            ELSE MAX(CASE WHEN rp.STATUS_CD = 1 THEN rp.NEW_MOV_DT END)
                 OVER (PARTITION BY rp.POLICY_TRANS_ID)
        END AS X_EMISSION_DT,

        -- X_PROCESSED_DT: complex logic based on status and events
        CASE
            WHEN rp.STATUS_CD NOT IN (2, 5, 9) THEN NULL
            WHEN rp.STATUS_CD = 9
                AND COALESCE(
                    LAG(rp.STATUS_CD::VARCHAR) OVER (PARTITION BY rp.POLICY_TRANS_ID ORDER BY rp."ORDER"),
                    ''
                ) NOT IN ('2', '3')
                AND e03.POLICY_TRANS_ID IS NULL
                AND NOT (rp.PROD_ID = '0850'
                    AND COALESCE(
                        LAG(rp.STATUS_CD::VARCHAR) OVER (PARTITION BY rp.POLICY_TRANS_ID ORDER BY rp."ORDER"),
                        ''
                    ) = '1')
                THEN NULL
            WHEN rp.PROD_ID = '0850' AND rp.STATUS_CD = 9
                AND COALESCE(
                    LAG(rp.STATUS_CD::VARCHAR) OVER (PARTITION BY rp.POLICY_TRANS_ID ORDER BY rp."ORDER"),
                    ''
                ) = '1'
                THEN rp.X_CREATION_DT
            ELSE COALESCE(e02.EVENT_DT, rp.X_CREATION_DT)
        END AS X_PROCESSED_DT,

        -- X_EXIT_DT: only when STATUS_CD = 2
        CASE WHEN rp.STATUS_CD = 2 THEN rp.NEW_MOV_DT ELSE NULL END AS X_EXIT_DT,

        -- X_RETURNED_DT: only when STATUS_CD = 3
        CASE WHEN rp.STATUS_CD = 3 THEN rp.NEW_MOV_DT ELSE NULL END AS X_RETURNED_DT,

        -- TRANS_DT: only when STATUS_CD = 5
        CASE WHEN rp.STATUS_CD = 5 THEN rp.NEW_MOV_DT ELSE NULL END AS TRANS_DT,

        -- X_CANCEL_DT: only when STATUS_CD = 9
        CASE WHEN rp.STATUS_CD = 9 THEN rp.X_CANCEL_DT ELSE NULL END AS X_CANCEL_DT,

        rp.X_PERIOD_FROM_DT,
        rp.X_PERIOD_TO_DT,

        -- String conversions of numeric codes
        TRIM(rp.TRANS_SUB_TYPE_CD::VARCHAR) AS TRANS_SUB_TYPE_CD,
        TRIM(rp.STATUS_CD::VARCHAR) AS X_TRANS_STATUS_CD,
        TRIM(rp.X_CANCEL_REASON_CD::VARCHAR) AS X_CANCEL_REASON_CD,

        -- X_TRANS_PREVIOUS_STATUS_CD: STATUS_CD of previous row in same group
        COALESCE(
            TRIM(LAG(rp.STATUS_CD) OVER (PARTITION BY rp.POLICY_TRANS_ID ORDER BY rp."ORDER")::VARCHAR),
            ''
        ) AS X_TRANS_PREVIOUS_STATUS_CD,

        rp.TRANS_GROSS_AMT,
        rp.TRANS_NET_AMT,
        rp.X_TRANS_PURE_AMT,
        rp.X_INEM_AMT,
        TRIM(rp.PAYMENT_METHOD_CD::VARCHAR) AS PAYMENT_METHOD_CD,
        rp.X_SUBS_CHARGE_AMT,
        rp.X_SUBS_FEE_AMT,
        rp.X_MANAGEMENT_FEE_AMT,
        TRIM(rp.X_REINVESTMENT_FLG::VARCHAR) AS X_REINVESTMENT_FLG,

        -- X_RET_REASON_CD from historical obs (only for status 3)
        CASE WHEN rp.STATUS_CD = 3 THEN rp.X_RET_REASON_CD_HO ELSE NULL END AS X_RET_REASON_CD,

        rp.X_IS_CLOSED_FLG,
        rp.AGENCY_INT_ID,

        -- X_CHARGEBACK_FLG: '0' if found in chargeback_rec, '1' otherwise
        CASE WHEN cb.POLICY_TRANS_ID IS NOT NULL THEN '0' ELSE '1' END AS X_CHARGEBACK_FLG,

        rp.PROD_ID

    FROM recibos_prd rp
    LEFT JOIN eventos02 e02 ON rp.POLICY_TRANS_ID = e02.POLICY_TRANS_ID
    LEFT JOIN eventos03 e03 ON rp.POLICY_TRANS_ID = e03.POLICY_TRANS_ID
    LEFT JOIN chargeback_rec cb ON rp.POLICY_TRANS_ID = cb.POLICY_TRANS_ID
),

--------------------------------------------------------------------
-- Step 17: Add Result Participation Flag
--------------------------------------------------------------------
with_participation AS (
    SELECT
        a.POLICY_TRANS_ID,
        a.POLICY_NO,
        a.PROPOSAL_NO,
        a.ORIGINAL_POLICY_TRANS_ID,
        a.X_MOV_DT,
        a.X_VALUE_DT,
        a.X_CREATION_DT,
        a.X_EMISSION_DT,
        a.X_PROCESSED_DT,
        a.X_EXIT_DT,
        a.X_RETURNED_DT,
        a.TRANS_DT,
        a.X_CANCEL_DT,
        a.X_PERIOD_FROM_DT,
        a.X_PERIOD_TO_DT,
        a.TRANS_SUB_TYPE_CD,
        a.X_TRANS_STATUS_CD,
        a.X_CANCEL_REASON_CD,
        a.X_TRANS_PREVIOUS_STATUS_CD,
        a.TRANS_GROSS_AMT,
        a.TRANS_NET_AMT,
        a.X_TRANS_PURE_AMT,
        a.X_INEM_AMT,
        a.PAYMENT_METHOD_CD,
        a.X_SUBS_CHARGE_AMT,
        a.X_SUBS_FEE_AMT,
        a.X_MANAGEMENT_FEE_AMT,
        a.X_REINVESTMENT_FLG,
        a.X_RET_REASON_CD,
        a.X_IS_CLOSED_FLG,
        a.AGENCY_INT_ID,
        a.X_CHARGEBACK_FLG,
        COALESCE(pf.X_RESULT_PARTICIPATION_FLG, '0') AS X_RESULT_PARTICIPATION_FLG
    FROM adjusted a
    LEFT JOIN participation_flag pf
        ON a.POLICY_TRANS_ID = pf.POLICY_TRANS_ID
        AND a.POLICY_NO = pf.POLICY_NO
)

--------------------------------------------------------------------
-- Step 18: Table Loader (final SELECT into target)
--------------------------------------------------------------------
SELECT
    POLICY_TRANS_ID::VARCHAR(32) AS POLICY_TRANS_ID,
    POLICY_NO::VARCHAR(32) AS POLICY_NO,
    PROPOSAL_NO::VARCHAR(32) AS PROPOSAL_NO,
    ORIGINAL_POLICY_TRANS_ID::VARCHAR(32) AS ORIGINAL_POLICY_TRANS_ID,
    X_MOV_DT::DATE AS X_MOV_DT,
    X_VALUE_DT::DATE AS X_VALUE_DT,
    X_CREATION_DT::DATE AS X_CREATION_DT,
    X_EMISSION_DT::DATE AS X_EMISSION_DT,
    X_PROCESSED_DT::DATE AS X_PROCESSED_DT,
    X_EXIT_DT::DATE AS X_EXIT_DT,
    X_RETURNED_DT::DATE AS X_RETURNED_DT,
    TRANS_DT::DATE AS TRANS_DT,
    X_CANCEL_DT::DATE AS X_CANCEL_DT,
    X_PERIOD_FROM_DT::DATE AS X_PERIOD_FROM_DT,
    X_PERIOD_TO_DT::DATE AS X_PERIOD_TO_DT,
    TRANS_SUB_TYPE_CD::VARCHAR(3) AS TRANS_SUB_TYPE_CD,
    X_TRANS_STATUS_CD::VARCHAR(3) AS X_TRANS_STATUS_CD,
    X_CANCEL_REASON_CD::VARCHAR(3) AS X_CANCEL_REASON_CD,
    X_TRANS_PREVIOUS_STATUS_CD::VARCHAR(3) AS X_TRANS_PREVIOUS_STATUS_CD,
    TRANS_GROSS_AMT::NUMBER(18,5) AS TRANS_GROSS_AMT,
    TRANS_NET_AMT::NUMBER(18,5) AS TRANS_NET_AMT,
    X_TRANS_PURE_AMT::NUMBER(18,5) AS X_TRANS_PURE_AMT,
    X_INEM_AMT::NUMBER(18,5) AS X_INEM_AMT,
    PAYMENT_METHOD_CD::VARCHAR(3) AS PAYMENT_METHOD_CD,
    X_SUBS_CHARGE_AMT::NUMBER(18,5) AS X_SUBS_CHARGE_AMT,
    X_SUBS_FEE_AMT::NUMBER(18,5) AS X_SUBS_FEE_AMT,
    X_MANAGEMENT_FEE_AMT::NUMBER(18,5) AS X_MANAGEMENT_FEE_AMT,
    X_REINVESTMENT_FLG::VARCHAR(1) AS X_REINVESTMENT_FLG,
    X_RET_REASON_CD::VARCHAR(4) AS X_RET_REASON_CD,
    X_IS_CLOSED_FLG::VARCHAR(1) AS X_IS_CLOSED_FLG,
    AGENCY_INT_ID::VARCHAR(32) AS AGENCY_INT_ID,
    X_CHARGEBACK_FLG::VARCHAR(1) AS X_CHARGEBACK_FLG,
    X_RESULT_PARTICIPATION_FLG::VARCHAR(3) AS X_RESULT_PARTICIPATION_FLG
FROM with_participation
;
