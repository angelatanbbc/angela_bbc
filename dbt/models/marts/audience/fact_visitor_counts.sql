{{ config(materialized="table") }}

-- A. DAILY COUNTS (Estimated from base states)
SELECT
    date_day AS date_period,
    'day' AS period_type,
    -- Estimate the distinct count from the daily HLL state
    HLL_ESTIMATE(daily_hll_state) AS approx_distinct_visitors
FROM {{ ref('int_daily_hll_states') }}

UNION ALL

-- B. WEEKLY AND MONTHLY COUNTS (Estimated from combined states)
SELECT
    CASE WHEN date_week IS NOT NULL THEN date_week ELSE date_month END AS date_period,
    CASE WHEN date_week IS NOT NULL THEN 'week' ELSE 'month' END AS period_type,
    -- Estimate the distinct count from the combined HLL state
    HLL_ESTIMATE(combined_hll_state) AS approx_distinct_visitors
FROM {{ ref('int_combined_hll_states') }}
WHERE date_week IS NOT NULL OR date_month IS NOT NULL