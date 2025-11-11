{{ config(
    materialized='incremental',
    unique_key=['date_day'],
    incremental_strategy='merge',
    on_schema_change='sync_all_columns'
) }}

SELECT
  -- Dimension Key: Date
  DATE_TRUNC(DAY, visit_time) AS date_day,
  
  -- Measure: The HLL state (a small binary object)
  HLL_ACCUMULATE(visitor_id) AS daily_hll_state 
FROM {{ ref('stg_piano_events__page_views') }}

{% if is_incremental() %}
-- Only process new data since the last run
WHERE visit_time >= (
    SELECT DATEADD(day, -1, MAX(date_day)) FROM {{ this }}
)
{% endif %}
GROUP BY 1