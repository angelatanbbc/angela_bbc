{{
    config(
        materialized="incremental",
        unique_key="pageview_id",
        incremental_strategy="merge",
        on_schema_change="sync_all_columns",
        tags=["piano", "fct", "page_views"]
    )
}}

/*
Page view fact table. Grain: one row per pageview_id (guaranteed by int_piano__page_views).
Scroll, click, ad impression and event duration measures are pre-aggregated to the
same grain in their intermediate models, so the left joins below cannot fan out.

Web page views only: Piano populates pageview_id for web (js) traffic only.
*/

WITH page_views AS (

    SELECT *
    FROM {{ ref('int_piano__page_views') }}
    WHERE 1 = 1
        {{ piano_page_view_event_window('page_view_time', 'page_view_time') }}

),

scrolls AS (

    SELECT
        pageview_id,
        scroll_depth_pct
    FROM {{ ref('int_piano__scroll_events') }}
    WHERE 1 = 1
        -- a page view in the window always has its last event in the window too
        {{ piano_page_view_event_window('last_event_time', 'page_view_time') }}

),

clicks AS (

    SELECT *
    FROM {{ ref('int_piano__click_events') }}
    WHERE 1 = 1
        -- a page view in the window always has its last event in the window too
        {{ piano_page_view_event_window('last_event_time', 'page_view_time') }}

),

ad_impressions AS (

    SELECT *
    FROM {{ ref('int_piano__ad_impressions') }}
    WHERE 1 = 1
        -- a page view in the window always has its last event in the window too
        {{ piano_page_view_event_window('last_event_time', 'page_view_time') }}

),

event_durations AS (

    SELECT
        pageview_id,
        event_duration_ms,
        events_with_duration_count
    FROM {{ ref('int_piano__event_durations') }}
    WHERE 1 = 1
        -- a page view in the window always has its last event in the window too
        {{ piano_page_view_event_window('last_event_time', 'page_view_time') }}

)

SELECT
    -- primary key
    pv.pageview_id,

    -- dimension surrogate keys
    {{ dbt_utils.generate_surrogate_key(['pv.content_id']) }} AS content_sk,
    {{ dbt_utils.generate_surrogate_key(['pv.user_id']) }} AS user_sk,
    {{ dbt_utils.generate_surrogate_key(['pv.visit_id']) }} AS visit_sk,
    {{ dbt_utils.generate_surrogate_key(['pv.geo_country_code_alpha2', 'pv.geo_region', 'pv.geo_city']) }} AS geography_sk,
    {{ dbt_utils.generate_surrogate_key(['pv.device_type', 'pv.os_group', 'pv.browser_group']) }} AS device_sk,
    {{ dbt_utils.generate_surrogate_key(['pv.site_id']) }} AS site_sk,

    -- natural keys kept for COUNT DISTINCT in the semantic layer
    pv.user_id,
    pv.visitor_id,
    pv.visit_id,
    pv.site_id,
    pv.visitor_new_return,
    pv.visitor_is_signed_in,

    -- timestamps (page view grain: first page.display event of the page view)
    pv.page_view_time,
    pv.page_view_time_utc,
    pv.page_view_time::DATE AS page_view_date,

    -- measures
    pv.page_display_event_count,
    COALESCE(pv.page_duration, 0) AS page_duration_seconds,
    -- visit_duration is session-level (seconds, rounded); event_duration_ms is
    -- summed event-level milliseconds. Piano's Time Spent / Visit filters on the
    -- former, Time Spent / Visitor on the latter, so keep both raw.
    COALESCE(pv.visit_duration, 0) AS visit_duration_seconds,
    COALESCE(ed.event_duration_ms, 0) AS event_duration_ms,
    COALESCE(ed.events_with_duration_count, 0) AS events_with_duration_count,
    COALESCE(s.scroll_depth_pct, 0) AS scroll_depth_pct,
    COALESCE(c.click_count, 0) AS click_count,
    COALESCE(c.action_click_count, 0) AS action_click_count,
    COALESCE(c.navigation_click_count, 0) AS navigation_click_count,
    COALESCE(c.exit_click_count, 0) AS exit_click_count,
    COALESCE(c.campaign_click_count, 0) AS campaign_click_count,
    COALESCE(c.viewability_select_count, 0) AS viewability_select_count,
    COALESCE(c.viewability_view_count, 0) AS viewability_view_count,
    COALESCE(c.subscription_select_count, 0) AS subscription_select_count,
    COALESCE(c.ad_click_count, 0) AS ad_click_count,
    COALESCE(c.internal_search_click_count, 0) AS internal_search_click_count,
    COALESCE(c.av_ad_click_count, 0) AS av_ad_click_count,
    COALESCE(c.newsletter_subscribe_count, 0) AS newsletter_subscribe_count,
    COALESCE(c.experience_interaction_count, 0) AS experience_interaction_count,
    COALESCE(ai.ad_impression_count, 0) AS ad_impression_count,
    COALESCE(ai.total_ad_revenue, 0) AS ad_revenue,
    COALESCE(ai.monetized_impression_count, 0) AS monetized_impression_count,
    COALESCE(ai.publisher_impression_count, 0) AS publisher_impression_count,
    COALESCE(ai.widget_impression_count, 0) AS widget_impression_count
FROM page_views pv
LEFT JOIN scrolls s ON pv.pageview_id = s.pageview_id
LEFT JOIN clicks c ON pv.pageview_id = c.pageview_id
LEFT JOIN ad_impressions ai ON pv.pageview_id = ai.pageview_id
LEFT JOIN event_durations ed ON pv.pageview_id = ed.pageview_id
