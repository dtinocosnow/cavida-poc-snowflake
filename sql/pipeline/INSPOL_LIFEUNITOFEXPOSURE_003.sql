CREATE OR REPLACE TRANSIENT TABLE CAVIDA_POC.STAGING.INSPOL_LIFEUNITOFEXPOSURE_003 AS
WITH
-- ==========================================================================
-- CTE: W6PQ20U
-- SAS Step: "Extract MAX Acta for Indiv Policies"
-- Description: Indiv Policies - comp coverages
-- Source: DB2_ACTA03_POC
-- ==========================================================================
W6PQ20U AS (
    SELECT DISTINCT
        "A3$MOD",
        "A3NAPO",
        "A3$CMP",
        "A3NORD",
        MAX("A3ACTA") AS "A3ACTA"
    FROM CAVIDA_POC.EXTRACTION.DB2_ACTA03_POC
    WHERE "A3$CMP" < 80
      AND "A3$MOD" <> 8
    GROUP BY
        "A3$MOD",
        "A3NAPO",
        "A3$CMP",
        "A3NORD"
),

-- ==========================================================================
-- CTE: W3746JH
-- SAS Step: "Extract MAX ACTA"
-- Description: MAX ACTA by MOD, NAPO, NORD (no CMP filter)
-- Source: DB2_ACTA03_POC
-- ==========================================================================
W3746JH AS (
    SELECT
        "A3$MOD",
        "A3NAPO",
        "A3NORD",
        MAX("A3ACTA") AS "A3ACTA"
    FROM CAVIDA_POC.EXTRACTION.DB2_ACTA03_POC
    GROUP BY
        "A3$MOD",
        "A3NAPO",
        "A3NORD"
),

-- ==========================================================================
-- CTE: W6QMRML
-- SAS Step: "Join - Data for all NORD's - ins. persons" (ACTA != 0)
-- Description: Indiv Policies - comp coverages - ACTA ne 0
-- INNER JOIN between W6PQ20U and DB2_APOL03_POC
-- ==========================================================================
W6QMRML AS (
    SELECT
        Db2_APOL03."A3$MOD" AS "AP$MOD",
        Db2_APOL03."A3NAPO" AS "APNAPO",
        Db2_APOL03."A3NORD" AS "APNORD",
        Db2_APOL03."A3$CMP",
        W6PQ20U."A3ACTA" AS "APACTA",
        Db2_APOL03."A3PREM" AS "APPREC",
        Db2_APOL03."A3CAPT" AS "APCAPT",
        Db2_APOL03."A3AINI" AS "APADAG",
        Db2_APOL03."A3MINI" AS "APMDAG",
        Db2_APOL03."A3DINI" AS "APDDAG",
        Db2_APOL03."A3SITU" AS "APSITU",
        TRY_TO_DATE(
            LPAD(Db2_APOL03."A3ASIT"::VARCHAR, 4, '0') ||
            LPAD(Db2_APOL03."A3MSIT"::VARCHAR, 2, '0') ||
            LPAD(Db2_APOL03."A3DSIT"::VARCHAR, 2, '0'),
            'YYYYMMDD'
        ) AS "APDTST"
    FROM W6PQ20U
    INNER JOIN CAVIDA_POC.EXTRACTION.DB2_APOL03_POC AS Db2_APOL03
        ON W6PQ20U."A3$MOD" = Db2_APOL03."A3$MOD"
       AND W6PQ20U."A3NAPO" = Db2_APOL03."A3NAPO"
       AND W6PQ20U."A3NORD" = Db2_APOL03."A3NORD"
       AND W6PQ20U."A3$CMP" = Db2_APOL03."A3$CMP"
),

-- ==========================================================================
-- CTE: W4KYHC4
-- SAS Step: "Join - Data for all NORD's - ins. persons" (ACTA=0)
-- Description: FULL JOIN with HAVING filters for matched rows (effectively INNER)
-- Source: DB2_APOL03_POC FULL JOIN W6PQ20U, WHERE + HAVING NOT IS MISSING
-- ==========================================================================
W4KYHC4 AS (
    SELECT
        Db2_APOL03."A3$MOD" AS "AP$MOD",
        Db2_APOL03."A3NAPO" AS "APNAPO",
        Db2_APOL03."A3$CMP",
        Db2_APOL03."A3NORD" AS "APNORD",
        W6PQ20U."A3ACTA" AS "APACTA",
        Db2_APOL03."A3PREM" AS "APPREC",
        Db2_APOL03."A3CAPT" AS "APCAPT",
        Db2_APOL03."A3AINI" AS "APADAG",
        Db2_APOL03."A3MINI" AS "APMDAG",
        Db2_APOL03."A3DINI" AS "APDDAG",
        Db2_APOL03."A3SITU" AS "APSITU",
        TRY_TO_DATE(
            LPAD(Db2_APOL03."A3ASIT"::VARCHAR, 4, '0') ||
            LPAD(Db2_APOL03."A3MSIT"::VARCHAR, 2, '0') ||
            LPAD(Db2_APOL03."A3DSIT"::VARCHAR, 2, '0'),
            'YYYYMMDD'
        ) AS "APDTST"
    FROM CAVIDA_POC.EXTRACTION.DB2_APOL03_POC AS Db2_APOL03
    FULL OUTER JOIN W6PQ20U
        ON Db2_APOL03."A3$MOD" = W6PQ20U."A3$MOD"
       AND Db2_APOL03."A3NAPO" = W6PQ20U."A3NAPO"
       AND Db2_APOL03."A3NORD" = W6PQ20U."A3NORD"
       AND Db2_APOL03."A3$CMP" = W6PQ20U."A3$CMP"
    WHERE Db2_APOL03."A3$CMP" < 80
      AND Db2_APOL03."A3$MOD" <> 8
      AND Db2_APOL03."A3$MOD" IS NOT NULL
      AND Db2_APOL03."A3NAPO" IS NOT NULL
),

-- ==========================================================================
-- CTE: W37NNZ6
-- SAS Step: "Join - Get Acta from Acta03"
-- Description: LEFT JOIN W4KYHC4 with W3746JH, COALESCE APACTA
-- ==========================================================================
W37NNZ6 AS (
    SELECT
        W4KYHC4."AP$MOD",
        W4KYHC4."APNAPO",
        W4KYHC4."A3$CMP",
        W4KYHC4."APNORD",
        COALESCE(W4KYHC4."APACTA", W3746JH."A3ACTA") AS "APACTA",
        W4KYHC4."APPREC",
        W4KYHC4."APCAPT",
        W4KYHC4."APADAG",
        W4KYHC4."APMDAG",
        W4KYHC4."APDDAG",
        W4KYHC4."APSITU",
        W4KYHC4."APDTST"
    FROM W4KYHC4
    LEFT JOIN W3746JH
        ON W4KYHC4."AP$MOD" = W3746JH."A3$MOD"
       AND W4KYHC4."APNAPO" = W3746JH."A3NAPO"
       AND W4KYHC4."APNORD" = W3746JH."A3NORD"
),

-- ==========================================================================
-- CTE: W42Y0WR
-- SAS Step: "Extract MAX Acta" (from ACTA00)
-- Description: MAX ACTA by MOD, NAPO from ACTA00
-- Source: DB2_ACTA00_POC
-- ==========================================================================
W42Y0WR AS (
    SELECT
        "A0$MOD",
        "A0NAPO",
        MAX("A0ACTA") AS "A0ACTA"
    FROM CAVIDA_POC.EXTRACTION.DB2_ACTA00_POC
    GROUP BY
        "A0$MOD",
        "A0NAPO"
),

-- ==========================================================================
-- CTE: W412UB1
-- SAS Step: "Join - Get Acta from ACTA00"
-- Description: LEFT JOIN W37NNZ6 with W42Y0WR, COALESCE APACTA with fallback 0
-- ==========================================================================
W412UB1 AS (
    SELECT
        W37NNZ6."AP$MOD",
        W37NNZ6."APNAPO",
        W37NNZ6."A3$CMP",
        W37NNZ6."APNORD",
        COALESCE(W37NNZ6."APACTA", W42Y0WR."A0ACTA", 0) AS "APACTA",
        W37NNZ6."APPREC",
        W37NNZ6."APCAPT",
        W37NNZ6."APADAG",
        W37NNZ6."APMDAG",
        W37NNZ6."APDDAG",
        W37NNZ6."APSITU",
        W37NNZ6."APDTST"
    FROM W37NNZ6
    LEFT JOIN W42Y0WR
        ON W37NNZ6."AP$MOD" = W42Y0WR."A0$MOD"
       AND W37NNZ6."APNAPO" = W42Y0WR."A0NAPO"
),

-- ==========================================================================
-- CTE: W5BFTDJ
-- SAS Step: "Extract - Indiv Policies"
-- Description: base coverage - ACTA ne 0
-- Source: DB2_ACTA00_POC
-- ==========================================================================
W5BFTDJ AS (
    SELECT DISTINCT
        "A0$MOD" AS "MOD",
        "A0NAPO",
        0 AS "NORD",
        0 AS "CMP",
        MAX("A0ACTA") AS "A0ACTA"
    FROM CAVIDA_POC.EXTRACTION.DB2_ACTA00_POC
    WHERE "A0INF4" <> 'S'
      AND "A0$APL" <> 0
      AND "A0$MOD" <> 8
    GROUP BY
        "A0$MOD",
        "A0NAPO"
),

-- ==========================================================================
-- CTE: WXBEZA
-- SAS Step: "Join - Add Dates and Other Info"
-- Description: Dates, Prems and Values
-- LEFT JOIN W5BFTDJ with DB2_ACTA00_POC
-- ==========================================================================
WXBEZA AS (
    SELECT
        W5BFTDJ."MOD",
        W5BFTDJ."A0NAPO",
        W5BFTDJ."NORD",
        W5BFTDJ."CMP",
        W5BFTDJ."A0ACTA",
        Db2_ACTA00."A0PRST" AS "APPREC",
        Db2_ACTA00."A0CTOT" AS "APCAPT",
        Db2_ACTA00."A0AINI",
        Db2_ACTA00."A0MINI",
        Db2_ACTA00."A0DINI",
        Db2_ACTA00."A0SITU",
        TRY_TO_DATE(
            LPAD(Db2_ACTA00."A0ASIT"::VARCHAR, 4, '0') ||
            LPAD(Db2_ACTA00."A0MSIT"::VARCHAR, 2, '0') ||
            LPAD(Db2_ACTA00."A0DSIT"::VARCHAR, 2, '0'),
            'YYYYMMDD'
        ) AS "SIT_DT"
    FROM W5BFTDJ
    LEFT JOIN CAVIDA_POC.EXTRACTION.DB2_ACTA00_POC AS Db2_ACTA00
        ON W5BFTDJ."MOD" = Db2_ACTA00."A0$MOD"
       AND W5BFTDJ."A0NAPO" = Db2_ACTA00."A0NAPO"
       AND W5BFTDJ."A0ACTA" = Db2_ACTA00."A0ACTA"
),

-- ==========================================================================
-- CTE: W4KWPAA
-- SAS Step: "Append"
-- Description: UNION ALL of W6QMRML + WXBEZA(renamed) + W412UB1
-- ==========================================================================
W4KWPAA AS (
    SELECT
        "AP$MOD", "APNAPO", "A3$CMP", "APNORD", "APACTA",
        "APPREC", "APCAPT", "APADAG", "APMDAG", "APDDAG",
        "APSITU", "APDTST"
    FROM W6QMRML

    UNION ALL

    SELECT
        "MOD" AS "AP$MOD",
        "A0NAPO" AS "APNAPO",
        "CMP" AS "A3$CMP",
        "NORD" AS "APNORD",
        "A0ACTA" AS "APACTA",
        "APPREC",
        "APCAPT",
        "A0AINI" AS "APADAG",
        "A0MINI" AS "APMDAG",
        "A0DINI" AS "APDDAG",
        "A0SITU" AS "APSITU",
        "SIT_DT" AS "APDTST"
    FROM WXBEZA

    UNION ALL

    SELECT
        "AP$MOD", "APNAPO", "A3$CMP", "APNORD", "APACTA",
        "APPREC", "APCAPT", "APADAG", "APMDAG", "APDDAG",
        "APSITU", "APDTST"
    FROM W412UB1
),

-- ==========================================================================
-- CTE: W4D9VYH
-- SAS Step: "Extract Coverages for Indiv Policies"
-- Description: Mappings (distinct)
-- Source: W4KWPAA
-- ==========================================================================
W4D9VYH AS (
    SELECT DISTINCT
        LPAD("AP$MOD"::VARCHAR, 2, '0') || LPAD("APNAPO"::VARCHAR, 8, '0') AS "PROPOSAL_NO",
        TRIM("A3$CMP"::VARCHAR) AS "X_COVERAGE_CD",
        TRIM("APNORD"::VARCHAR) AS "X_ORDER_CD",
        "APACTA" AS "POLICY_VERSION",
        "APPREC" / 100 AS "ANNUAL_PREMIUM_AMT",
        "APCAPT" / 100 AS "CASH_VALUE",
        TRY_TO_DATE(
            LPAD("APADAG"::VARCHAR, 4, '0') ||
            LPAD("APMDAG"::VARCHAR, 2, '0') ||
            LPAD("APDDAG"::VARCHAR, 2, '0'),
            'YYYYMMDD'
        ) AS "ADMISSION_DT",
        TRIM("APSITU"::VARCHAR) AS "X_ORDER_STATUS",
        CASE
            WHEN "APSITU" <> 0 THEN
                TRY_TO_DATE(
                    LPAD("APADAG"::VARCHAR, 4, '0') ||
                    LPAD("APMDAG"::VARCHAR, 2, '0') ||
                    LPAD("APDDAG"::VARCHAR, 2, '0'),
                    'YYYYMMDD'
                )
            ELSE NULL
        END AS "EFFECTIVE_DT"
    FROM W4KWPAA
),

-- ==========================================================================
-- CTE: WVKBK4
-- SAS Step: "Extract Info on Policies from Most Recent Data"
-- Description: Mappings from APOL00
-- Source: DB2_APOL00_POC
-- ==========================================================================
WVKBK4 AS (
    SELECT DISTINCT
        LPAD("A0$MOD"::VARCHAR, 2, '0') || LPAD("A0$APL"::VARCHAR, 8, '0') AS "POLICY_NO",
        LPAD("A0$MOD"::VARCHAR, 2, '0') || LPAD("A0NAPO"::VARCHAR, 8, '0') AS "X_PROPOSAL_NO",
        TRY_TO_DATE(
            LPAD("A0AFIM"::VARCHAR, 4, '0') ||
            LPAD("A0MFIM"::VARCHAR, 2, '0') ||
            LPAD("A0DFIM"::VARCHAR, 2, '0'),
            'YYYYMMDD'
        ) AS "TERMINATION_DT",
        TRY_TO_DATE(
            LPAD("A0ASIT"::VARCHAR, 4, '0') ||
            LPAD("A0MSIT"::VARCHAR, 2, '0') ||
            LPAD("A0DSIT"::VARCHAR, 2, '0'),
            'YYYYMMDD'
        ) AS "UOE_STATUS_DT",
        TRY_TO_DATE(
            LPAD("A0AEFE"::VARCHAR, 4, '0') ||
            LPAD("A0MEFE"::VARCHAR, 2, '0') ||
            LPAD("A0DEFE"::VARCHAR, 2, '0'),
            'YYYYMMDD'
        ) AS "UOE_MOD_DT",
        CASE
            WHEN TRIM("A0SITU"::VARCHAR) = '.' THEN ''
            ELSE TRIM("A0SITU"::VARCHAR)
        END AS "UOE_STATUS_CD",
        "A0ACTA" AS "POLICY_VERSION",
        "A0PRSC" / 100 AS "ANNUAL_PREMIUM_AMT",
        "A0CTOT" / 100 AS "CASH_VALUE",
        "A0HINI",
        "A0AINI",
        "A0MINI",
        "A0DINI",
        "A0AFIM",
        "A0MFIM",
        "A0DFIM",
        "A0INF4" AS "Inf4",
        "A0$APL"
    FROM CAVIDA_POC.EXTRACTION.DB2_APOL00_POC
),

-- ==========================================================================
-- CTE: W4FIP3F
-- SAS Step: "Join - Add Policy Info"
-- Description: Indiv Policies - Remove proposals that not yet become policies
-- RIGHT JOIN WVKBK4 with W4D9VYH, HAVING filters
-- ==========================================================================
W4FIP3F AS (
    SELECT
        WVKBK4."POLICY_NO",
        W4D9VYH."PROPOSAL_NO",
        W4D9VYH."X_COVERAGE_CD",
        W4D9VYH."X_ORDER_CD",
        W4D9VYH."POLICY_VERSION",
        W4D9VYH."ANNUAL_PREMIUM_AMT",
        W4D9VYH."CASH_VALUE",
        W4D9VYH."ADMISSION_DT",
        W4D9VYH."X_ORDER_STATUS",
        TRY_TO_DATE(
            LPAD(WVKBK4."A0AINI"::VARCHAR, 4, '0') ||
            LPAD(WVKBK4."A0MINI"::VARCHAR, 2, '0') ||
            LPAD(WVKBK4."A0DINI"::VARCHAR, 2, '0'),
            'YYYYMMDD'
        ) AS "EFFECTIVE_DT",
        WVKBK4."TERMINATION_DT",
        TRY_TO_DATE(
            LPAD(WVKBK4."A0AINI"::VARCHAR, 4, '0') ||
            LPAD(WVKBK4."A0MINI"::VARCHAR, 2, '0') ||
            LPAD(WVKBK4."A0DINI"::VARCHAR, 2, '0'),
            'YYYYMMDD'
        )::TIMESTAMP_NTZ AS "CHANGE_EFFECTIVE_FROM_DTTM",
        WVKBK4."UOE_STATUS_CD" AS "POLICY_STATUS_CD",
        TRY_TO_DATE(
            LPAD(WVKBK4."A0AFIM"::VARCHAR, 4, '0') ||
            LPAD(WVKBK4."A0MFIM"::VARCHAR, 2, '0') ||
            LPAD(WVKBK4."A0DFIM"::VARCHAR, 2, '0'),
            'YYYYMMDD'
        ) AS "EXPIRATION_DT",
        WVKBK4."Inf4",
        WVKBK4."A0$APL" AS "ApolAPL"
    FROM WVKBK4
    RIGHT JOIN W4D9VYH
        ON WVKBK4."X_PROPOSAL_NO" = W4D9VYH."PROPOSAL_NO"
       AND WVKBK4."POLICY_VERSION" = W4D9VYH."POLICY_VERSION"
    WHERE WVKBK4."Inf4" <> 'S'
      AND WVKBK4."A0$APL" <> 0
      AND WVKBK4."POLICY_NO" IS NOT NULL
      AND WVKBK4."POLICY_NO" <> ''
),

-- ==========================================================================
-- CTE: W4HC1S2
-- SAS Step: "Join - Add Renewable Ind and Indexation Rate" (1st)
-- Description: LEFT JOIN with ACTA03 and ACTA00 for indexation/renewable
-- ==========================================================================
W4HC1S2 AS (
    SELECT
        COALESCE(
            W4FIP3F."POLICY_NO",
            LPAD(Db2_ACTA00."A0$MOD"::VARCHAR, 2, '0') || LPAD(Db2_ACTA00."A0$APL"::VARCHAR, 8, '0')
        ) AS "POLICY_NO",
        W4FIP3F."PROPOSAL_NO",
        W4FIP3F."X_COVERAGE_CD",
        W4FIP3F."X_ORDER_CD",
        W4FIP3F."POLICY_VERSION",
        W4FIP3F."ANNUAL_PREMIUM_AMT",
        W4FIP3F."CASH_VALUE",
        COALESCE(Db2_ACTA00."A0INDX", Db2_ACTA03."A3INDX") AS "X_INDEXATION_RT",
        COALESCE(Db2_ACTA00."A0DURC"::VARCHAR(1), Db2_ACTA03."A3DURC"::VARCHAR(1)) AS "RENEWABLE_IND",
        W4FIP3F."ADMISSION_DT",
        W4FIP3F."X_ORDER_STATUS",
        COALESCE(
            TRY_TO_DATE(
                LPAD(Db2_ACTA00."A0AEFE"::VARCHAR, 4, '0') ||
                LPAD(Db2_ACTA00."A0MEFE"::VARCHAR, 2, '0') ||
                LPAD(Db2_ACTA00."A0DEFE"::VARCHAR, 2, '0'),
                'YYYYMMDD'
            ),
            W4FIP3F."EFFECTIVE_DT"
        ) AS "EFFECTIVE_DT",
        W4FIP3F."TERMINATION_DT",
        COALESCE(
            TRY_TO_DATE(
                LPAD(Db2_ACTA00."A0AEFE"::VARCHAR, 4, '0') ||
                LPAD(Db2_ACTA00."A0MEFE"::VARCHAR, 2, '0') ||
                LPAD(Db2_ACTA00."A0DEFE"::VARCHAR, 2, '0'),
                'YYYYMMDD'
            )::TIMESTAMP_NTZ,
            W4FIP3F."CHANGE_EFFECTIVE_FROM_DTTM"
        ) AS "CHANGE_EFFECTIVE_FROM_DTTM",
        W4FIP3F."POLICY_STATUS_CD",
        W4FIP3F."EXPIRATION_DT"
    FROM W4FIP3F
    LEFT JOIN CAVIDA_POC.EXTRACTION.DB2_ACTA03_POC AS Db2_ACTA03
        ON W4FIP3F."PROPOSAL_NO" = LPAD(Db2_ACTA03."A3$MOD"::VARCHAR, 2, '0') || LPAD(Db2_ACTA03."A3NAPO"::VARCHAR, 8, '0')
       AND W4FIP3F."POLICY_VERSION" = Db2_ACTA03."A3ACTA"
       AND TRY_TO_NUMBER(W4FIP3F."X_ORDER_CD") = Db2_ACTA03."A3NORD"
       AND TRY_TO_NUMBER(W4FIP3F."X_COVERAGE_CD") = Db2_ACTA03."A3$CMP"
    LEFT JOIN CAVIDA_POC.EXTRACTION.DB2_ACTA00_POC AS Db2_ACTA00
        ON W4FIP3F."PROPOSAL_NO" = LPAD(Db2_ACTA00."A0$MOD"::VARCHAR, 2, '0') || LPAD(Db2_ACTA00."A0NAPO"::VARCHAR, 8, '0')
       AND W4FIP3F."POLICY_VERSION" = Db2_ACTA00."A0ACTA"
),

-- ==========================================================================
-- CTE: WJER4K7
-- SAS Step: "Join - Add Renewable Ind and Indexation Rate" (2nd/final)
-- Description: LEFT JOIN with APOL03 where POLICY_VERSION=0, add CHANGE_EFFECTIVE_TO_DTTM
-- Final work table before load to target
-- ==========================================================================
WJER4K7 AS (
    SELECT
        W4HC1S2."POLICY_NO",
        W4HC1S2."PROPOSAL_NO",
        W4HC1S2."X_COVERAGE_CD",
        W4HC1S2."X_ORDER_CD",
        W4HC1S2."POLICY_VERSION",
        W4HC1S2."ANNUAL_PREMIUM_AMT",
        W4HC1S2."CASH_VALUE",
        COALESCE(W4HC1S2."X_INDEXATION_RT", Db2_APOL03."A3INDX") AS "X_INDEXATION_RT",
        COALESCE(W4HC1S2."RENEWABLE_IND", Db2_APOL03."A3DURC"::VARCHAR(1)) AS "RENEWABLE_IND",
        W4HC1S2."ADMISSION_DT",
        W4HC1S2."X_ORDER_STATUS",
        W4HC1S2."EFFECTIVE_DT",
        W4HC1S2."TERMINATION_DT",
        W4HC1S2."CHANGE_EFFECTIVE_FROM_DTTM",
        '5999-01-01 00:00:00'::TIMESTAMP_NTZ AS "CHANGE_EFFECTIVE_TO_DTTM",
        W4HC1S2."POLICY_STATUS_CD",
        W4HC1S2."EXPIRATION_DT"
    FROM W4HC1S2
    LEFT JOIN CAVIDA_POC.EXTRACTION.DB2_APOL03_POC AS Db2_APOL03
        ON LPAD(Db2_APOL03."A3$MOD"::VARCHAR, 2, '0') || LPAD(Db2_APOL03."A3NAPO"::VARCHAR, 8, '0') = W4HC1S2."PROPOSAL_NO"
       AND Db2_APOL03."A3NORD" = TRY_TO_NUMBER(W4HC1S2."X_ORDER_CD")
       AND Db2_APOL03."A3$CMP" = TRY_TO_NUMBER(W4HC1S2."X_COVERAGE_CD")
       AND W4HC1S2."POLICY_VERSION" = 0
    WHERE REPLACE(REPLACE(W4HC1S2."POLICY_NO", ' ', ''), '.', '') <> ''
)

-- ==========================================================================
-- Final SELECT into target table
-- Target: CAVIDA_POC.STAGING.INSPOL_LIFEUNITOFEXPOSURE_003
-- ==========================================================================
SELECT
    "POLICY_NO"::VARCHAR(32) AS "POLICY_NO",
    "PROPOSAL_NO"::VARCHAR(32) AS "PROPOSAL_NO",
    "X_COVERAGE_CD"::VARCHAR(8) AS "X_COVERAGE_CD",
    "X_ORDER_CD"::VARCHAR(8) AS "X_ORDER_CD",
    "POLICY_VERSION"::NUMBER(38,0) AS "POLICY_VERSION",
    "ANNUAL_PREMIUM_AMT"::NUMBER(38,2) AS "ANNUAL_PREMIUM_AMT",
    "CASH_VALUE"::NUMBER(38,2) AS "CASH_VALUE",
    "X_INDEXATION_RT"::NUMBER(38,6) AS "X_INDEXATION_RT",
    "RENEWABLE_IND"::VARCHAR(1) AS "RENEWABLE_IND",
    "ADMISSION_DT"::DATE AS "ADMISSION_DT",
    "X_ORDER_STATUS"::VARCHAR(1) AS "X_ORDER_STATUS",
    "EFFECTIVE_DT"::DATE AS "EFFECTIVE_DT",
    "TERMINATION_DT"::DATE AS "TERMINATION_DT",
    "CHANGE_EFFECTIVE_FROM_DTTM"::TIMESTAMP_NTZ AS "CHANGE_EFFECTIVE_FROM_DTTM",
    "CHANGE_EFFECTIVE_TO_DTTM"::TIMESTAMP_NTZ AS "CHANGE_EFFECTIVE_TO_DTTM",
    "POLICY_STATUS_CD"::VARCHAR(3) AS "POLICY_STATUS_CD",
    "EXPIRATION_DT"::DATE AS "EXPIRATION_DT"
FROM WJER4K7;
