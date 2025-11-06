{{
    config(
        materialized="incremental",
        unique_key=['date', 'visitor_id'],
        incremental_strategy='merge',
        on_schema_change='sync_all_columns'
    )
}}

SELECT DISTINCT
    visit_time::DATE AS date,
    visitor_id
FROM {{ ref('stg_piano_events__page_views') }}
WHERE 1=1
{% if is_incremental() %}
    AND visit_time::DATE >= DATEADD(DAY, -1, (SELECT MAX(date) FROM {{ this }}))
{% endif %}
