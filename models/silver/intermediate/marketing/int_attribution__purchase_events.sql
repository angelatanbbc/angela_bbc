{{
    config(
        materialized="incremental",
        incremental_strategy="merge",
        unique_key="conversion_id",
        on_schema_change="fail",
        tags=["attribution", "intermediate"]
    )
}}

/*
Purchase events: one row per conversion_id, its first vx.conversion event with a
pageview_id, on any site. Incremental so the Piano events are scanned a day at a time.
*/

{%- set floor = incremental_date_floor('event_time') %}

WITH new_events AS (

    SELECT
        conversion_id,
        subscription_id,
        pageview_id,
        visitor_id,
        IFF(user_id ILIKE 'unidentified%', NULL, NULLIF(user_id, '')) AS user_id,
        device_first_party_id,
        event_time,
        billing_period,
        vx_promo_code,
        {%- for column in attribution_touch_columns() %}
        {{ column }},
        {%- endfor %}
        app_type
    FROM {{ ref('int_piano__events_cleaned') }}
    WHERE
        event_name = 'vx.conversion'
        AND conversion_id IS NOT NULL
        AND pageview_id IS NOT NULL
        {%- if floor %}
        AND event_time >= '{{ floor }}'
        {%- endif %}
    QUALIFY ROW_NUMBER() OVER (PARTITION BY conversion_id ORDER BY event_time) = 1

)

SELECT
    conversion_id,
    subscription_id,
    pageview_id,
    visitor_id,
    user_id,
    device_first_party_id,
    event_time,
    billing_period,
    vx_promo_code,
    {%- for column in attribution_touch_columns() %}
    {{ column }},
    {%- endfor %}
    app_type
FROM new_events n
{%- if is_incremental() %}
WHERE NOT EXISTS (
    SELECT 1
    FROM {{ this }} t
    WHERE
        t.conversion_id = n.conversion_id
        AND t.event_time <= n.event_time
)
{%- endif %}
