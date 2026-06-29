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
        AND experience_id IN (SELECT DISTINCT dim_experience.experience_id
                              FROM {{ ref('dim_experience') }}
                              WHERE dim_experience.app_type_id = MD5('Web'))
        AND template_name != 'Outside Region Error Message'
        {% if is_incremental() %}
            AND event_time::DATE >= DATEADD(DAY, -1, (SELECT MAX(exposure_time)::DATE FROM {{ this }}))
        {% endif %}

),

-- Use attributes from Piano Analytics events (page.display) instead of Composer attributes since there are various issues
-- issues with the Composer attributes. Join back to the page.display events using pageview_id to get the relevant attributes for exposures.
experience_actions AS (
    
    SELECT
        *,
        {{ dbt_utils.generate_surrogate_key(['experience_execution_id', 'event_time']) }} AS exposure_id

    FROM composer_events
    WHERE event_name = 'experience.action'

)

SELECT
    -- Exposure Info
    exposure_id,
    experience_execution_id,
    event_time AS exposure_time,
    event_time::DATE AS exposure_date,
    pageview_id,

    -- Visitor / Device Info
    visitor_id,
    visit_id,
    user_id,
    MD5('Web') AS app_type_id,
    device_type_id,
    os_group_id,

    -- Page Info
    page,
    page_title,
    page_content_type,
    content_type,
    content_id,
    content_section,
    content_topic,
    content_pillar,
    date_published,
    url,

    -- Geography
    geo_id,
    geo_country,
    geo_region,
    geo_city,

    -- Experience Info
    experience_id,
    experience_name,
    card_id,
    card_name,
    card_action,
    template_id,
    template_name,
    ab_test_card_title,
    ab_test_variant_name,

    -- C1X attributes
    c1x_lts,
    c1x_content_likely_to_convert,
    c1x_likelihood_to_register,
    c1x_likelihood_to_return,
    c1x_revenue_auto_optimization

FROM experience_actions
