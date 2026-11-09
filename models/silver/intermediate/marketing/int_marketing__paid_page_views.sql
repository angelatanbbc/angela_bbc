{{
    config(
        materialized="incremental",
        incremental_strategy="delete+insert",
        unique_key="visit_date",
        on_schema_change="append_new_columns",
        full_refresh=false,
        tags=["marketing", "intermediate"]
    )
}}

/*
The page views of paid visits: one row per page view of a visit in int_marketing__paid_visits,
including the few whose own tag Piano left empty. Measures come from fct_page_views and labels from
int_piano__page_views. The 'unidentified-user' placeholder is never an account here.
Incremental on visit_date, the same days as int_marketing__paid_visits (see marketing_batch_window).
*/

{%- set window = marketing_batch_window() %}

WITH paid_visits AS (

    SELECT
        visit_id,
        visit_date,
        ad_sk,
        ad_id,
        agency,
        agency_resolved_from,
        src_campaign,
        visit_bounce
    FROM {{ ref('int_marketing__paid_visits') }}
    {%- if window %}
    WHERE {{ attribution_window_predicate(window, 'visit_date') }}
    {%- endif %}

),

page_views AS (

    SELECT
        pageview_id,
        visit_id,
        visitor_id,
        user_id,
        device_first_party_id,
        site_id,
        page_view_time,
        page_view_date,
        visitor_new_return,
        page_duration_seconds,
        visit_duration_seconds,
        newsletter_subscribe_count,
        subscription_select_count
    FROM {{ ref('fct_page_views') }}
    WHERE
        {{ marketing_page_view_predicate(window, 'page_view_time') }}
        AND visit_id IN (SELECT pv.visit_id FROM paid_visits pv)

),

labels AS (

    SELECT
        pageview_id,
        content_id,
        content_pillar,
        content_section,
        content_type,
        page_content_type,
        page_title,
        device_platform_id,
        browser_group,
        geo_country,
        geo_region,
        c1x_revenue_auto_optimization,
        c1x_lts
    FROM {{ ref('int_piano__page_views') }}
    WHERE
        {{ marketing_page_view_predicate(window, 'page_view_time') }}
        AND visit_id IN (SELECT pv.visit_id FROM paid_visits pv)

),

purchases AS (

    SELECT
        checkout_pageview_id AS pageview_id,
        COUNT(*) AS vx_conversion_count
    FROM {{ ref('int_attribution__conversions') }}
    GROUP BY checkout_pageview_id

)

SELECT
    p.pageview_id,
    p.visit_id,
    p.visitor_id,
    IFF(p.user_id ILIKE 'unidentified%', NULL, NULLIF(p.user_id, '')) AS user_id,
    p.device_first_party_id,
    v.ad_sk,
    {{ generate_geo_id('l.geo_country', 'l.geo_region') }} AS geo_id,
    l.device_platform_id,
    p.site_id,
    v.visit_date,
    p.page_view_date,
    p.page_view_time,
    v.agency,
    v.agency_resolved_from,
    v.ad_id,
    v.src_campaign,
    p.visitor_new_return,
    v.visit_bounce AS is_visit_bounce,
    {{ parse_score_lower_bound('l.c1x_revenue_auto_optimization') }} AS ro_lower_bound_pct,
    {{ parse_score_lower_bound('l.c1x_lts') }} AS lts_lower_bound_pct,
    l.content_id,
    l.content_pillar,
    l.content_section,
    l.content_type,
    l.page_content_type,
    l.page_title,
    l.browser_group,
    l.geo_country,
    l.geo_region,
    p.page_duration_seconds,
    p.visit_duration_seconds,
    p.newsletter_subscribe_count,
    p.subscription_select_count,
    COALESCE(c.vx_conversion_count, 0) AS vx_conversion_count
FROM page_views p
JOIN paid_visits v ON p.visit_id = v.visit_id
LEFT JOIN labels l ON p.pageview_id = l.pageview_id
LEFT JOIN purchases c ON p.pageview_id = c.pageview_id
