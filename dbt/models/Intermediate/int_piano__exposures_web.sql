{{
    config(
        materialized="incremental",
        unique_key="exposure_id",
        incremental_strategy='merge',
        on_schema_change='sync_all_columns'
    )
}}

WITH composer_events AS (

    SELECT *
    FROM {{ ref('stg_piano__composer_events') }}
    WHERE
        event_name IN ('experience.action', 'experience.interaction', 'vx.conversion')
        AND experience_id != 'EXFXDKMDXAX0' -- Policy Modal
        AND template_name != 'Outside Region Error Message'
        {% if is_incremental() %}
            AND event_time::DATE >= DATEADD(DAY, -1, (SELECT MAX(exposure_time)::DATE FROM {{ this }}))
        {% endif %}

),

-- Use attributes from Piano Analytics events (page.display) instead of Composer attributes since there are various issues
-- issues with the Composer attributes. Join back to the page.display events using pageview_id to get the relevant attributes for exposures.
pageview_join AS (
    
    SELECT
        ce.experience_execution_id,
        ce.event_time AS exposure_time,
        ce.pageview_id,

        -- Inherit from Piano Analytics using pageview_id
        pv.visitor_id,
        pv.visit_id,
        pv.user_id,
        pv.device_type,
        pv.app_type,
        pv.os_group,

        -- Page Info
        pv.page,
        pv.page_title,
        pv.page_content_type,
        pv.content_id,
        pv.page_url,
        pv.page_url_domain,
        pv.page_url_full,

        -- Geography
        pv.geo_id,
        pv.geo_country,
        pv.geo_region,
        pv.geo_city,

        -- Experience Info
        ce.experience_id,
        ce.experience_name,
        ce.card_id,
        ce.card_name,
        ce.card_action,
        ce.template_id,
        ce.template_name,
        ce.ab_test_card_title,
        ce.ab_test_variant_name

    FROM composer_events ce
    JOIN {{ ref('fact_page_views') }} pv USING (pageview_id)
    WHERE ce.event_name = 'experience.action'

    
),

-- If the visitor had experience.interaction event on the same pageview_id, experience_id, card_id
-- and template_id then flag that they interacted with the experience, otherwise just exposed to it
interactions AS (

    SELECT
        pv.*,
        IFNULL(MAX(ce.event_name = 'experience.interaction'), FALSE) AS is_interacted_with,
        IFNULL(MAX(ce.event_name = 'vx.conversion'), FALSE) AS is_last_touch_conversion
    FROM pageview_join pv
    LEFT JOIN composer_events ce
        ON pv.pageview_id = ce.pageview_id
        AND pv.experience_id = ce.experience_id
        AND pv.card_id = ce.card_id
        AND pv.template_id = ce.template_id
        AND ce.event_name IN ('experience.interaction', 'vx.conversion')
    GROUP BY ALL

)

SELECT
    {{dbt_utils.generate_surrogate_key(['experience_execution_id', 'exposure_time'])}} AS exposure_id,
    *
FROM interactions
