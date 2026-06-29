{{
    config(
        materialized="incremental",
        unique_key="exposure_id",
        incremental_strategy='merge',
        on_schema_change='sync_all_columns'
    )
}}

WITH composer_events AS (

    SELECT
        c.experience_execution_id,
        c.event_time AS exposure_time,
        c.event_time::DATE AS exposure_date,
        c.pageview_id,

        -- Inherit from Piano Analytics using pageview_id
        c.visitor_id,
        c.visit_id,
        c.user_id,
        e.app_type_id,
        c.device_type_id,
        c.os_group_id,

        -- Page Info
        NULL AS page,
        NULL AS page_title,
        NULL AS page_content_type,
        NULL AS content_id,
        NULL AS page_url,
        NULL AS page_url_domain,
        NULL AS page_url_full,

        -- Geography
        c.geo_id,
        c.geo_country,
        c.geo_region,
        c.geo_city,

        -- Experience Info
        c.experience_id,
        c.experience_name,
        c.card_id,
        c.card_name,
        c.card_action,
        c.template_id,
        c.template_name,
        c.ab_test_card_title,
        c.ab_test_variant_name,

        -- C1X attributes
        NULL AS c1x_lts,
        NULL AS c1x_content_likely_to_convert,
        NULL AS c1x_likelihood_to_register,
        NULL AS c1x_likelihood_to_return,
        NULL AS c1x_revenue_auto_optimization

    FROM {{ ref('stg_piano__composer_events') }} c
    JOIN {{ ref('dim_experience') }} e USING (experience_id)
    WHERE
        c.event_name = 'experience.action'
        AND c.event_collection_platform = 'da-composer-vx'
        AND e.app_type_id = MD5('Mobile App')
        {% if is_incremental() %}
            AND c.event_time::DATE >= DATEADD(DAY, -1, (SELECT MAX(exposure_time)::DATE FROM {{ this }}))
        {% endif %}

),

-- If the visitor had experience.interaction event on the same pageview_id, experience_id, card_id
-- and template_id then flag that they interacted with the experience, otherwise just exposed to it
interactions AS (

    SELECT
        e.*,
        BOOLOR_AGG(i.experience_execution_id IS NOT NULL) AS is_interacted_with,
        NULL AS is_last_touch_conversion
    FROM composer_events e
    LEFT JOIN {{ ref('stg_piano__composer_events') }} i
        ON i.event_name = 'experience.interaction'
        AND e.experience_execution_id = i.experience_execution_id
    GROUP BY ALL

)

SELECT
    {{dbt_utils.generate_surrogate_key(['experience_execution_id', 'exposure_time'])}} AS exposure_id,
    *
FROM interactions
