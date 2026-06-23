{{ config(
    materialized='incremental',
    unique_key='pageview_id',
    incremental_strategy='merge',
    on_schema_change='sync_all_columns'
) }}


-- Get page view events from collected by Piano Analytics
WITH web_page_views AS (

    SELECT *
    FROM {{ ref('stg_piano__analytics_events') }}
    WHERE
        app_type = 'Web'
        AND pageview_id IS NOT NULL
        {% if is_incremental() %}
            AND event_time::DATE >= DATEADD(DAY, -1, (SELECT MAX(pageview_time)::DATE FROM {{ this }}))
        {% endif %}
        AND geo_country = 'United states' -- Temporary filter to focus on US market, will remove later

),

-- Get flags for whether a paywall or ribbon experience was shown on each pageview
web_composer_flags AS (

    SELECT
        pageview_id,
        MAX(c1x_lts) AS c1x_lts,
        MAX(c1x_content_likely_to_convert) AS c1x_content_likely_to_convert,
        MAX(c1x_likelihood_to_register) AS c1x_likelihood_to_register,
        MAX(c1x_likelihood_to_return) AS c1x_likelihood_to_return,
        MAX(c1x_revenue_auto_optimization) AS c1x_revenue_auto_optimization,
        MAX(c1x_brand_relationship) AS c1x_brand_relationship,
        MAX(c1x_checkout_abandonment) AS c1x_checkout_abandonment,
        MAX(c1x_subscription_length) AS c1x_subscription_length,
        MAX(c1x_subscription_tenure) AS c1x_subscription_tenure,
        MAX(c1x_expiring_subscribers) AS c1x_expiring_subscribers,
        COUNT(DISTINCT experience_id) AS num_composer_experiences_shown,
        MAX(IFF(template_name ILIKE '%gate%', true, false)) AS is_paywall_shown,
        MAX(IFF(template_name ILIKE '%ribbon%', true, false)) AS is_ribbon_shown
    FROM {{ ref('stg_piano__composer_events') }}
    WHERE
        event_name IN ('experience.action', 'experience.interaction', 'vx.conversion')
        AND pageview_id IS NOT NULL
        {% if is_incremental() %}
            AND event_time::DATE >= DATEADD(DAY, -2, (SELECT MAX(pageview_time)::DATE FROM {{ this }}))
        {% endif %}
    GROUP BY pageview_id

)

SELECT
    pageview_id,
    pv.event_time AS pageview_time,
    pv.event_time::DATE AS pageview_date,

    -- IDs
    pv.visitor_id,
    pv.visit_id,
    pv.user_id,
    pv.user_first_party_id,

    -- Acquisition / visit source
    pv.src,
    pv.src_detail,
    pv.src_url,

    -- Device / App
    pv.device_type,
    pv.app_type,
    pv.app_name,
    pv.os_group,

    -- Page Info
    pv.page,
    pv.page_title,
    pv.page_content_type,
    pv.content_type,
    pv.content_id,
    pv.content_section,
    pv.content_topic,
    pv.content_pillar,
    pv.date_published,
    pv.url AS content_url,
    pv.event_url AS page_url,
    pv.event_url_domain AS page_url_domain,
    pv.event_url_full AS page_url_full,

    -- Geography
    pv.geo_id,
    IFNULL(pv.geo_country, 'Unknown') AS geo_country,
    IFNULL(pv.geo_region, 'Unknown') AS geo_region,
    IFNULL(pv.geo_city, 'Unknown') AS geo_city,

    -- C1X Fields
    cf.c1x_lts,
    cf.c1x_content_likely_to_convert,
    cf.c1x_likelihood_to_register,
    cf.c1x_likelihood_to_return,
    cf.c1x_revenue_auto_optimization,
    cf.c1x_brand_relationship,
    cf.c1x_checkout_abandonment,
    cf.c1x_subscription_length,
    cf.c1x_subscription_tenure,
    cf.c1x_expiring_subscribers,

    -- Composer flags
    COALESCE(cf.num_composer_experiences_shown, 0) AS num_composer_experiences_shown,
    COALESCE(cf.is_paywall_shown, FALSE) AS is_paywall_shown,
    COALESCE(cf.is_ribbon_shown, FALSE) AS is_ribbon_shown,
    pv.c1x_brand_relationship AS pageview_c1x_brand_relationship,
    pv.c1x_brand_relationship IN ('Paid trial users', 'Subscribers') AS is_paid_trial_or_subscriber,

FROM web_page_views pv
LEFT JOIN web_composer_flags cf USING (pageview_id)

-- In case there are multiple page.display events for the same pageview_id, take the earliest one
QUALIFY ROW_NUMBER() OVER (PARTITION BY pageview_id ORDER BY pageview_time) = 1
