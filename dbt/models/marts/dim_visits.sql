{{
    config(
        materialized="incremental",
        unique_key='visit_id',
        incremental_strategy='merge',
        on_schema_change='sync_all_columns'
    )
}}

SELECT
    visit_id,
    visit_time,
    visitor_id,
    user_id,
    device_type,
    src,
    src_detail,
    first_event_time,
    last_event_time
    
FROM {{ ref('int_visit_aggregation') }}

{% if is_incremental() %}

WHERE visit_time::DATE >= (SELECT MAX(visit_time::DATE) FROM {{ this }})

{% endif %}