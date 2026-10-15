{{
    config(
        materialized="incremental",
        unique_key="pageview_id",
        incremental_strategy="merge",
        on_schema_change="sync_all_columns",
        tags=["piano", "intermediate"]
    )
}}

/*
Page view pool: one row per pageview_id.

The events table can contain multiple page.display events for the same page view
(e.g. re-fires, SPA updates). This model defines the page view concept once:
- page_duration is the max across duplicate events
- page_view_time is the first event's timestamp
- descriptive attributes are taken from the latest event
Downstream models read from here, so the grain is guaranteed everywhere. Scroll
depth is NOT here: it arrives on separate page.scroll events and is rolled up in
int_piano__scroll_events.

Only page.display events with a pageview_id are kept. Piano populates pageview_id
for web (js) traffic only, so native app page views are not in this model.
*/

WITH page_display_events AS (

    SELECT *
    FROM {{ ref('int_piano__events_cleaned') }}
    WHERE
        event_name = 'page.display'
        AND pageview_id IS NOT NULL
        {{ piano_page_view_event_window() }}

),

pageview_grain AS (

    SELECT
        *,
        MAX(page_duration) OVER (PARTITION BY pageview_id) AS page_duration_agg,
        MIN(event_time) OVER (PARTITION BY pageview_id) AS page_view_time,
        MIN(event_time_utc) OVER (PARTITION BY pageview_id) AS page_view_time_utc,
        MAX(event_time) OVER (PARTITION BY pageview_id) AS last_event_time,
        -- Piano's Pageviews definition counts distinct page.display event_ids,
        -- so duplicate events for one pageview_id each count
        COUNT(DISTINCT event_id) OVER (PARTITION BY pageview_id) AS page_display_event_count
    FROM page_display_events
    QUALIFY ROW_NUMBER() OVER (PARTITION BY pageview_id ORDER BY event_time DESC) = 1

)

SELECT
    -- identifiers
    pageview_id,
    visit_id,
    visitor_id,
    user_id,
    site_id,
    content_id,

    -- timestamps
    page_view_time,
    page_view_time_utc,
    last_event_time,
    visit_time,
    visit_time_utc,

    -- measures
    page_display_event_count,
    page_duration_agg AS page_duration,

    -- page / content labels
    page,
    page_full_name,
    page_chapter1,
    page_chapter2,
    page_chapter3,
    page_aisle1,
    page_aisle2,
    page_aisle3,
    page_title,
    page_content_type,
    url,
    referrer_url,

    -- content metadata
    content_type,
    content_topic,
    content_brand,
    content_section,
    content_authors,
    content_publication_date,
    content_article_name,
    content_pillar,
    content_edition,
    content_format,
    content_collection,
    content_licence,

    -- user / visitor
    visitor_new_return,
    visitor_is_signed_in,
    user_category,
    user_recognition,
    user_first_party_id,
    device_first_party_id,

    -- visit / session
    visit_duration,
    visit_bounce,
    visit_entrypage,
    visit_entrypage_full_name,
    visit_exitpage,
    visit_exitpage_full_name,
    visit_page_views,
    visit_implication_degree,
    visit_converted,

    -- traffic source
    src,
    src_type,
    src_medium,
    src_campaign,
    src_campaign_type,
    src_detail,
    src_organic,
    src_organic_detail,
    src_referrer_url,
    src_bbc_team,
    src_creative_id,
    src_creation,
    src_ptr_name,
    src_adset_name,
    src_adset_id,
    src_objective,
    src_format,
    src_sl_term,
    utm_source,
    utm_medium,
    utm_campaign,
    utm_content,
    utm_term,

    -- campaign tags parsed from the landing URL
    url_at_bbc_team,
    url_at_creative_id,
    url_at_campaign,
    url_at_link_origin,
    url_at_ptr_name,
    url_at_adset_name,
    url_at_adset_id,
    url_at_objective,
    url_at_medium,
    url_at_matchtype,
    url_at_keyword,
    url_at_creation,
    url_at_campaign_name,

    -- geography
    geo_continent,
    geo_country,
    geo_country_code_alpha2,
    geo_region,
    geo_city,
    geo_metro,

    -- device / browser / OS / app
    app_type,
    device_type,
    os_group,
    browser_group,

    -- site
    site_level2,
    site_env,
    orga_id,

    -- Composer template (populated on experience events only, so normally NULL on page.display)
    template_display_mode,
    template_closable
FROM pageview_grain
