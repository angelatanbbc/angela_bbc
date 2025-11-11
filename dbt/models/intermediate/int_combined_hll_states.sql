{{ config(materialized="table") }}

SELECT
  -- Grouping for the weekly rollup
  DATE_TRUNC('week', date_day) AS date_week,
  -- Grouping for the monthly rollup
  DATE_TRUNC('month', date_day) AS date_month,

  -- Combine all the daily HLL states within that group
  HLL_COMBINE(daily_hll_state) AS combined_hll_state
FROM {{ ref('int_daily_hll_states') }}
GROUP BY 1,2
