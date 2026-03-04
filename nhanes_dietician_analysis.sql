-- NHANES 2021-2023: Diet-Related Condition Cohort Analysis

-- Explores healthcare access patterns across four diet-related conditions (obesity, diabetes, high cholesterol, high blood pressure)
-- Each condition uses only respondents who actually answered that question, excluding nulls, refusals, (code 7), and don't knows (code 9):

-- QUERY 1: DATA OVERVIEW

SELECT
    d.seqn,
    d.ridageyr                                          AS age,
    d.riagendr                                          AS gender,            -- 1=Male 2=Female
    d.ridreth3                                          AS race_ethnicity,    -- 1=Mexican American 2=Other Hispanic 3=Non-Hispanic White 4=Non-Hispanic Black 6=Non-Hispanic Asian
    d.indfmpir                                          AS income_poverty_ratio,

    b.bmxbmi                                            AS bmxbmi,
    diq.diq010                                          AS diq010_raw,        -- 1=Yes 2=No 3=Borderline 7=Refused 9=Don't know
    bpq.bpq020                                          AS bpq020_raw,        -- 1=Yes 2=No 7=Refused 9=Don't know
    bpq.bpq080                                          AS bpq080_raw,        -- 1=Yes 2=No 7=Refused 9=Don't know

    -- CONDITION FLAGS
    CASE WHEN b.bmxbmi >= 30               THEN 1 ELSE 0 END AS is_obese,
    CASE WHEN b.bmxbmi BETWEEN 25 AND 29.9 THEN 1 ELSE 0 END AS is_overweight,
    CASE WHEN diq.diq010 IN (1,3)          THEN 1 ELSE 0 END AS has_diabetes,
    CASE WHEN bpq.bpq020 = 1              THEN 1 ELSE 0 END AS has_hypertension,
    CASE WHEN bpq.bpq080 = 1              THEN 1 ELSE 0 END AS has_high_cholesterol,

    -- INSURANCE
    CASE WHEN hiq.hiq011 = 1 THEN 'Insured' ELSE 'Uninsured' END AS insurance_status,

    -- HEALTHCARE UTILIZATION
    hu.huq010                                           AS general_health,       -- 1=Excellent 2=Very good 3=Good 4=Fair 5=Poor
    CASE WHEN hu.huq030 = 2 THEN 1 ELSE 0 END          AS no_usual_care_place,
    hu.huq042                                           AS usual_care_type,      -- 1=Doctor/health center 2=Urgent care 3=ER 4=VA 5=Other
    CASE WHEN hu.huq055 = 1 THEN 1 ELSE 0 END          AS had_telehealth_visit,
    CASE WHEN hu.huq090 = 1 THEN 1 ELSE 0 END          AS saw_mental_health_pro

FROM demographics d
LEFT JOIN body_measures    b   ON d.seqn = b.seqn
LEFT JOIN diabetes         diq ON d.seqn = diq.seqn
LEFT JOIN bp_cholesterol_q bpq ON d.seqn = bpq.seqn
LEFT JOIN insurance        hiq ON d.seqn = hiq.seqn
LEFT JOIN healthcare_util  hu  ON d.seqn = hu.seqn
WHERE d.ridageyr >= 18
LIMIT 100;


-- QUERY 2: CONDITION PREVALENCE OVERVIEW
-- ============================================================
-- Sizes each condition cohort with insured/uninsured split.
-- Percentages use condition-specific denominators to exclude respondents who didn't 
-- answer or have no measurement (explaining why % of adults for each column aren't in line with Total row)
-- ============================================================

WITH cohort AS (
    SELECT
        d.seqn,
        b.bmxbmi                                            AS bmxbmi,
        diq.diq010                                          AS diq010_raw,
        bpq.bpq020                                          AS bpq020_raw,
        bpq.bpq080                                          AS bpq080_raw,
        -- Condition flags
        CASE WHEN b.bmxbmi >= 30      THEN 1 ELSE 0 END     AS is_obese,
        CASE WHEN diq.diq010 IN (1,3) THEN 1 ELSE 0 END     AS has_diabetes,
        CASE WHEN bpq.bpq020 = 1     THEN 1 ELSE 0 END     AS has_hypertension,
        CASE WHEN bpq.bpq080 = 1     THEN 1 ELSE 0 END     AS has_high_cholesterol,
        CASE WHEN hiq.hiq011 = 1 THEN 'Insured' ELSE 'Uninsured' END AS insurance_status
    FROM demographics d
    LEFT JOIN body_measures    b   ON d.seqn = b.seqn
    LEFT JOIN diabetes         diq ON d.seqn = diq.seqn
    LEFT JOIN bp_cholesterol_q bpq ON d.seqn = bpq.seqn
    LEFT JOIN insurance        hiq ON d.seqn = hiq.seqn
    WHERE d.ridageyr >= 18
)


 SELECT 'All Adults (overall)'   AS condition, sum(CASE WHEN bmxbmi is not null then 1 else 0 end) AS total_respondents,
 --only respondents with a valid BMI measurement,
 SUM(CASE WHEN insurance_status = 'Insured'   AND bmxbmi IS NOT NULL THEN 1 ELSE 0 END) AS insured,
 SUM(CASE WHEN insurance_status = 'Uninsured' AND bmxbmi IS NOT NULL THEN 1 ELSE 0 END) AS uninsured,
ROUND(100.0 * SUM(CASE WHEN bmxbmi IS NOT NULL THEN 1 ELSE 0 END) /
        SUM(CASE WHEN bmxbmi IS NOT NULL THEN 1 ELSE 0 END), 1)   AS   pct_of_adults
 FROM cohort 
    UNION ALL

SELECT
    'Obesity'           AS condition,
    SUM(is_obese)       AS total_respondents,
    SUM(CASE WHEN insurance_status = 'Insured'   THEN is_obese ELSE 0 END) AS insured,
    SUM(CASE WHEN insurance_status = 'Uninsured' THEN is_obese ELSE 0 END) AS uninsured,
    -- Denominator: only respondents with a valid BMI measurement
    ROUND(100.0 * SUM(is_obese) /
        SUM(CASE WHEN bmxbmi IS NOT NULL THEN 1 ELSE 0 END), 1)            AS pct_of_adults
FROM cohort
UNION ALL
SELECT
    'Diabetes (incl. borderline)',
    SUM(has_diabetes),
    SUM(CASE WHEN insurance_status = 'Insured'   THEN has_diabetes ELSE 0 END),
    SUM(CASE WHEN insurance_status = 'Uninsured' THEN has_diabetes ELSE 0 END),
    -- Denominator: only respondents who answered diq010 (1=Yes, 2=No, 3=Borderline)
    ROUND(100.0 * SUM(has_diabetes) /
        SUM(CASE WHEN diq010_raw IN (1,2,3) THEN 1 ELSE 0 END), 1)
FROM cohort
UNION ALL
SELECT
    'Hypertension',
    SUM(has_hypertension),
    SUM(CASE WHEN insurance_status = 'Insured'   THEN has_hypertension ELSE 0 END),
    SUM(CASE WHEN insurance_status = 'Uninsured' THEN has_hypertension ELSE 0 END),
    -- Denominator: only respondents who answered bpq020 (1=Yes, 2=No)
    ROUND(100.0 * SUM(has_hypertension) /
        SUM(CASE WHEN bpq020_raw IN (1,2) THEN 1 ELSE 0 END), 1)
FROM cohort
UNION ALL
SELECT
    'High Cholesterol',
    SUM(has_high_cholesterol),
    SUM(CASE WHEN insurance_status = 'Insured'   THEN has_high_cholesterol ELSE 0 END),
    SUM(CASE WHEN insurance_status = 'Uninsured' THEN has_high_cholesterol ELSE 0 END),
    -- Denominator: only respondents who answered bpq080 (asked of a subset)
    ROUND(100.0 * SUM(has_high_cholesterol) /
        SUM(CASE WHEN bpq080_raw IN (1,2) THEN 1 ELSE 0 END), 1)
FROM cohort;


-- ============================================================
-- QUERY 3: HEALTHCARE ACCESS BY CONDITION & INSURANCE
-- ============================================================
-- For each condition cohort split by insurance status, shows:
--   - % with no usual place for care (access gap)
--   - % whose usual care is an ER (relying on emergency care)
--   - % who used telehealth in past 12 months
--   - Average self-reported health score (1=Excellent, 5=Poor)
-- Each UNION branch filters to its condition-specific valid
-- respondents so the n and percentages are accurate.
-- ============================================================

WITH cohort AS (
    SELECT
        d.seqn,
        b.bmxbmi,
        diq.diq010 AS diq010_raw,
        bpq.bpq020 AS bpq020_raw,
        bpq.bpq080 AS bpq080_raw,
        CASE WHEN b.bmxbmi >= 30      THEN 1 ELSE 0 END     AS is_obese,
        CASE WHEN diq.diq010 IN (1,3) THEN 1 ELSE 0 END     AS has_diabetes,
        CASE WHEN bpq.bpq020 = 1      THEN 1 ELSE 0 END     AS has_hypertension,
        CASE WHEN bpq.bpq080 = 1      THEN 1 ELSE 0 END     AS has_high_cholesterol,
        CASE WHEN hiq.hiq011 = 1 THEN 'Insured' ELSE 'Uninsured' END AS insurance_status,
        CASE WHEN hu.huq030 = 2 THEN 1 ELSE 0 END           AS no_usual_care_place,
        CASE WHEN hu.huq042 = 3 THEN 1 ELSE 0 END           AS er_is_usual_care,
        CASE WHEN hu.huq055 = 1 THEN 1 ELSE 0 END           AS had_telehealth,
        CASE WHEN hu.huq090 = 1 THEN 1 ELSE 0 END           AS had_mental_counseling,
        hu.huq010                                           AS health_score
    FROM demographics d
    LEFT JOIN body_measures    b   ON d.seqn = b.seqn
    LEFT JOIN diabetes         diq ON d.seqn = diq.seqn
    LEFT JOIN bp_cholesterol_q bpq ON d.seqn = bpq.seqn
    LEFT JOIN insurance        hiq ON d.seqn = hiq.seqn
    LEFT JOIN healthcare_util  hu  ON d.seqn = hu.seqn
    WHERE d.ridageyr >= 18
)
SELECT
    condition,
    insurance_status,
    COUNT(*)                                               AS n,
    ROUND(100.0 * SUM(no_usual_care_place) / COUNT(*), 1)  AS pct_no_usual_care,
    ROUND(100.0 * SUM(er_is_usual_care)    / COUNT(*), 1)  AS pct_er_as_usual_care,
    ROUND(100.0 * SUM(had_telehealth)      / COUNT(*), 1)  AS pct_used_telehealth,
    ROUND(100.0 * SUM(had_mental_counseling)     / COUNT(*),1) as pct_mental_counseling,
    ROUND(AVG(CAST(health_score AS FLOAT)), 2)             AS avg_health_score
FROM (
    SELECT 'Overall Respondents' AS condition, insurance_status, no_usual_care_place, er_is_usual_care, had_telehealth, had_mental_counseling, health_score
        FROM cohort
    UNION ALL
    SELECT 'Obesity' AS condition, insurance_status, no_usual_care_place, er_is_usual_care, had_telehealth, had_mental_counseling, health_score
        FROM cohort WHERE bmxbmi IS NOT NULL AND is_obese = 1
    UNION ALL
    SELECT 'Diabetes' AS condition, insurance_status, no_usual_care_place, er_is_usual_care, had_telehealth, had_mental_counseling, health_score
        FROM cohort WHERE diq010_raw IN (1,2,3) AND has_diabetes = 1
    UNION ALL
    SELECT 'Hypertension' AS condition, insurance_status, no_usual_care_place, er_is_usual_care, had_telehealth, had_mental_counseling, health_score
        FROM cohort WHERE bpq020_raw IN (1,2) AND has_hypertension = 1
    UNION ALL
    SELECT 'High Cholesterol' AS condition, insurance_status, no_usual_care_place, er_is_usual_care, had_telehealth, had_mental_counseling, health_score
        FROM cohort WHERE bpq080_raw IN (1,2) AND has_high_cholesterol = 1
) sub
GROUP BY condition, insurance_status
ORDER BY 
    CASE WHEN condition = 'Overall Respondents' THEN 0 ELSE 1 END, 
    condition, 
    insurance_status;
-- ============================================================
-- QUERY 4: COMORBIDITY BURDEN
-- ============================================================
-- Groups respondents by how many of the 4 conditions they have.
-- Condition count only increments when the respondent has valid
-- data for that condition. Respondents with data for fewer than
-- 3 conditions are excluded to avoid skewing the 0-count bucket.
-- ============================================================

WITH cohort AS (
    SELECT
        d.seqn,
       -- CASE WHEN hiq.hiq011 = 1 THEN 'Insured' ELSE 'Uninsured' END AS insurance_status,
        CASE WHEN hu.huq030 = 2 THEN 1 ELSE 0 END          AS no_usual_care_place,
        CASE WHEN hu.huq042 = 3 THEN 1 ELSE 0 END          AS er_is_usual_care,
        CASE WHEN hu.huq055 = 1 THEN 1 ELSE 0 END          AS had_telehealth,
        hu.huq010                                           AS health_score,
        -- Valid data flags
        CASE WHEN b.bmxbmi IS NOT NULL     THEN 1 ELSE 0 END AS has_bmi_data,
        CASE WHEN diq.diq010 IN (1,2,3)    THEN 1 ELSE 0 END AS has_diabetes_data,
        CASE WHEN bpq.bpq020 IN (1,2)      THEN 1 ELSE 0 END AS has_bp_data,
        CASE WHEN bpq.bpq080 IN (1,2)      THEN 1 ELSE 0 END AS has_chol_data,
        -- Condition count: only increments when respondent has valid data for that condition
        (CASE WHEN b.bmxbmi IS NOT NULL     AND b.bmxbmi >= 30      THEN 1 ELSE 0 END +
         CASE WHEN diq.diq010 IN (1,2,3)    AND diq.diq010 IN (1,3) THEN 1 ELSE 0 END +
         CASE WHEN bpq.bpq020 IN (1,2)      AND bpq.bpq020 = 1      THEN 1 ELSE 0 END +
         CASE WHEN bpq.bpq080 IN (1,2)      AND bpq.bpq080 = 1      THEN 1 ELSE 0 END
        )                                                   AS condition_count
    FROM demographics d
    LEFT JOIN body_measures    b   ON d.seqn = b.seqn
    LEFT JOIN diabetes         diq ON d.seqn = diq.seqn
    LEFT JOIN bp_cholesterol_q bpq ON d.seqn = bpq.seqn
    --LEFT JOIN insurance        hiq ON d.seqn = hiq.seqn
    LEFT JOIN healthcare_util  hu  ON d.seqn = hu.seqn
    WHERE d.ridageyr >= 18
)
SELECT
    CASE condition_count
        WHEN 0 THEN '0 - No conditions'
        WHEN 1 THEN '1 - Single condition'
        WHEN 2 THEN '2 - Two conditions'
        WHEN 3 THEN '3 - Three conditions'
        WHEN 4 THEN '4 - All four conditions'
    END                                                     AS comorbidity_level,
    -- insurance_status,
    COUNT(*)                                                AS n,
    ROUND(100.0 * SUM(no_usual_care_place) / COUNT(*), 1)  AS pct_no_usual_care,
    ROUND(100.0 * SUM(er_is_usual_care)    / COUNT(*), 1)  AS pct_er_as_usual_care,
    ROUND(100.0 * SUM(had_telehealth)      / COUNT(*), 1)  AS pct_used_telehealth,
    ROUND(AVG(CAST(health_score AS FLOAT)), 2)             AS avg_health_score
FROM cohort
-- Only include respondents with valid data for at least 3 of 4 conditions
WHERE (has_bmi_data + has_diabetes_data + has_bp_data + has_chol_data) >= 3
GROUP BY condition_count
ORDER BY condition_count;


-- ============================================================
-- QUERY 5: HIGH VALUE COHORTS
-- ============================================================
-- Groups respondents by age and gender, identifying which cohorts
-- may be most willing to use a telehealth nutrition platform.
-- % of cohort that has tried to lose weight during the past 12 mo's
-- for a health related reason
-- % of cohort that has used telehealth services over past 12 mo's
-- ============================================================

WITH cohort AS (
		SELECT
			d.seqn, w.whq070, hu.huq055, dt.drqsdiet,
			CASE WHEN d.riagendr = 1 THEN 'Male' 
						WHEN d.riagendr = 2 THEN 'Female' ELSE 0 END AS gender,
			CASE WHEN w.whq070 = 1 THEN 1 ELSE 0 END AS trying_to_lose_weight,
			CASE WHEN hiq.hiq011 = 1 THEN 'Insured' ELSE 'Uninsured' END AS insurance_status,
			CASE when ridageyr BETWEEN 18 and 25 THEN "18-25"
			when ridageyr BETWEEN 26 and 35 THEN "26-35"
			when ridageyr BETWEEN 36 and 45 THEN "36-45"
			when ridageyr BETWEEN 46 and 55 THEN "46-55"
			when ridageyr BETWEEN 56 and 65 THEN "56-65"
			when ridageyr BETWEEN 66 and 75 THEN "66-75"
			when ridageyr BETWEEN 76 and 80 THEN "76+"
			ELSE "<18"
			END AS Age_Group,
			CASE WHEN hu.huq055 = 1 THEN 1 ELSE 0 END          AS had_telehealth,
			CASE WHEN dt.drqsdiet = 1 THEN 1 ELSE 0 END          AS on_diet
			from demographics d
			LEFT JOIN healthcare_util hu on d.seqn=hu.seqn
			LEFT JOIN body_measures    b   ON d.seqn = b.seqn
			LEFT JOIN diabetes         diq ON d.seqn = diq.seqn
			LEFT JOIN bp_cholesterol_q bpq ON d.seqn = bpq.seqn
			LEFT JOIN insurance        hiq ON d.seqn = hiq.seqn
			LEFT JOIN weight_history        w ON d.seqn = w.seqn
			LEFT JOIN dietary_total_day1       dt ON d.seqn = dt
			.seqn
			WHERE d.ridageyr >= 18
)
SELECT
gender, Age_Group, 
ROUND(100.0*sum(trying_to_lose_weight)/sum(CASE WHEN whq070 IS NOT NULL THEN 1 ELSE 0 END), 1) AS pct_of_adults_trying_to_lose_weight,
ROUND(100.0*sum(on_diet)/sum(CASE WHEN drqsdiet IS NOT NULL THEN 1 ELSE 0 END), 1) AS pct_of_adults_on_diet,
ROUND(100.0*sum(had_telehealth)/sum(CASE WHEN huq055 IS NOT NULL THEN 1 ELSE 0 END), 1) AS pct_used_telehealth
from cohort
group by gender, age_group
 
 UNION ALL
SELECT
    'OVERALL', 'OVERALL', 
    ROUND(100.0*sum(trying_to_lose_weight)/sum(CASE WHEN whq070 IS NOT NULL THEN 1 ELSE 0 END), 1),
	ROUND(100.0*sum(on_diet)/sum(CASE WHEN drqsdiet IS NOT NULL THEN 1 ELSE 0 END), 1) ,
    ROUND(100.0*sum(had_telehealth)/sum(CASE WHEN huq055 IS NOT NULL THEN 1 ELSE 0 END), 1)
FROM cohort;


-- ============================================================
-- QUERY 6: MEDICATION BURDEN BY CONDITION 
-- ============================================================
-- For each condition cohort, shows:
--   - n: respondents with valid medication data
--   - pct_on_any_rx: % currently taking any prescription drug
--   - avg_rx_count: average number of medications among those
--     taking any (a proxy for treatment complexity)
--   - pct_polypharmacy: % on 3+ medications simultaneously
--     (elevated cost burden on payers)
-- ============================================================

WITH cohort AS (
    SELECT
        d.seqn,
        b.bmxbmi                                            AS bmxbmi,
        diq.diq010                                          AS diq010_raw,
        bpq.bpq020                                          AS bpq020_raw,
        bpq.bpq080                                          AS bpq080_raw,
        CASE WHEN b.bmxbmi >= 30      THEN 1 ELSE 0 END     AS is_obese,
        CASE WHEN diq.diq010 IN (1,3) THEN 1 ELSE 0 END     AS has_diabetes,
        CASE WHEN bpq.bpq020 = 1     THEN 1 ELSE 0 END     AS has_hypertension,
        CASE WHEN bpq.bpq080 = 1     THEN 1 ELSE 0 END     AS has_high_cholesterol,
        rx.rxq050                                           AS rx_count,
        CASE WHEN rx.rxq033 = 1      THEN 1 ELSE 0 END     AS on_any_rx,
        CASE WHEN rx.rxq050 >= 3     THEN 1 ELSE 0 END     AS is_polypharmacy
    FROM demographics d
    LEFT JOIN body_measures    b   ON d.seqn = b.seqn
    LEFT JOIN diabetes         diq ON d.seqn = diq.seqn
    LEFT JOIN bp_cholesterol_q bpq ON d.seqn = bpq.seqn
    LEFT JOIN medications      rx  ON d.seqn = rx.seqn
    WHERE d.ridageyr >= 18
      AND rx.rxq033 IN (1,2)
)
SELECT
    condition,
    COUNT(*)                                                AS n,
    ROUND(100.0 * SUM(on_any_rx)      / COUNT(*), 1)       AS pct_on_any_rx,
    ROUND(AVG(CASE WHEN on_any_rx = 1
              THEN CAST(rx_count AS FLOAT) END), 2)        AS avg_rx_count,
    ROUND(100.0 * SUM(is_polypharmacy) / COUNT(*), 1)      AS pct_polypharmacy
FROM (
    -- All respondents with valid data (overall benchmark row)
    SELECT 'All Adults (overall)'   AS condition, on_any_rx, rx_count, is_polypharmacy
        FROM cohort WHERE bmxbmi IS NOT NULL
    UNION ALL
    SELECT 'Obesity'                AS condition, on_any_rx, rx_count, is_polypharmacy
        FROM cohort WHERE bmxbmi IS NOT NULL     AND is_obese = 1
    UNION ALL
    SELECT 'Diabetes'               AS condition, on_any_rx, rx_count, is_polypharmacy
        FROM cohort WHERE diq010_raw IN (1,2,3) AND has_diabetes = 1
    UNION ALL
    SELECT 'Hypertension'           AS condition, on_any_rx, rx_count, is_polypharmacy
        FROM cohort WHERE bpq020_raw IN (1,2)   AND has_hypertension = 1
    UNION ALL
    SELECT 'High Cholesterol'       AS condition, on_any_rx, rx_count, is_polypharmacy
        FROM cohort WHERE bpq080_raw IN (1,2)   AND has_high_cholesterol = 1
) sub
GROUP BY condition
ORDER BY CASE condition
    WHEN 'All Adults (overall)' THEN 0
    WHEN 'Obesity'              THEN 1
    WHEN 'Diabetes'             THEN 2
    WHEN 'Hypertension'         THEN 3
    WHEN 'High Cholesterol'     THEN 4
END;


-- ============================================================
-- QUERY 7: PRESCRIPTIONS BY COMORBIDITY LEVEL
-- ============================================================
-- Shows how medication count escalates as condition burden
-- increases from 0 to 4 conditions (obesity, diabetes, 
-- high blood pressure, hypertension). 
-- conclusion: each additional diet-related condition adds
-- measurable pharmaceutical burden for payers.
-- ============================================================

WITH cohort AS (
    SELECT
        d.seqn,
        -- Medication variables
        rx.rxq033                                           AS took_rx,
        rx.rxq050                                           AS rx_count,
        CASE WHEN rx.rxq033 = 1  THEN 1 ELSE 0 END         AS on_any_rx,
        CASE WHEN rx.rxq050 >= 3 THEN 1 ELSE 0 END         AS is_polypharmacy,
        CASE WHEN rx.rxq050 >= 5 THEN 1 ELSE 0 END         AS is_high_polypharmacy, -- 5+ meds
        -- Valid data flags
        CASE WHEN b.bmxbmi IS NOT NULL     THEN 1 ELSE 0 END AS has_bmi_data,
        CASE WHEN diq.diq010 IN (1,2,3)    THEN 1 ELSE 0 END AS has_diabetes_data,
        CASE WHEN bpq.bpq020 IN (1,2)      THEN 1 ELSE 0 END AS has_bp_data,
        CASE WHEN bpq.bpq080 IN (1,2)      THEN 1 ELSE 0 END AS has_chol_data,
        -- Condition count: only increments with valid data
        (CASE WHEN b.bmxbmi IS NOT NULL     AND b.bmxbmi >= 30      THEN 1 ELSE 0 END +
         CASE WHEN diq.diq010 IN (1,2,3)    AND diq.diq010 IN (1,3) THEN 1 ELSE 0 END +
         CASE WHEN bpq.bpq020 IN (1,2)      AND bpq.bpq020 = 1      THEN 1 ELSE 0 END +
         CASE WHEN bpq.bpq080 IN (1,2)      AND bpq.bpq080 = 1      THEN 1 ELSE 0 END
        )                                                   AS condition_count
    FROM demographics d
    LEFT JOIN body_measures    b   ON d.seqn = b.seqn
    LEFT JOIN diabetes         diq ON d.seqn = diq.seqn
    LEFT JOIN bp_cholesterol_q bpq ON d.seqn = bpq.seqn
    LEFT JOIN insurance        hiq ON d.seqn = hiq.seqn
    LEFT JOIN medications      rx  ON d.seqn = rx.seqn
    WHERE d.ridageyr >= 18
      AND rx.rxq033 IN (1,2)
)
SELECT
    CASE condition_count
        WHEN 0 THEN '0 - No conditions'
        WHEN 1 THEN '1 - Single condition'
        WHEN 2 THEN '2 - Two conditions'
        WHEN 3 THEN '3 - Three conditions'
        WHEN 4 THEN '4 - All four conditions'
    END                                                     AS comorbidity_level,
    COUNT(*)                                                AS n,
    ROUND(100.0 * SUM(on_any_rx)           / COUNT(*), 1)  AS pct_on_any_rx,
    ROUND(AVG(CASE WHEN on_any_rx = 1
              THEN CAST(rx_count AS FLOAT) END), 2)        AS avg_rx_count,
    ROUND(100.0 * SUM(is_polypharmacy)     / COUNT(*), 1)  AS pct_polypharmacy_3plus,
    ROUND(100.0 * SUM(is_high_polypharmacy)/ COUNT(*), 1)  AS pct_polypharmacy_5plus
FROM cohort
WHERE (has_bmi_data + has_diabetes_data + has_bp_data + has_chol_data) >= 3
GROUP BY condition_count
ORDER BY condition_count;