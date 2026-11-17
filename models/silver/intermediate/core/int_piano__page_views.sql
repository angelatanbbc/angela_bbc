{{
    config(
        materialized="incremental",
        unique_key="pageview_id",
        incremental_strategy="merge",
        incremental_predicates=piano_page_view_merge_predicates('page_view_time', 'last_event_time'),
        on_schema_change="sync_all_columns",
        full_refresh=false,
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

Built without sorting or windowing wide rows, which spilled terabytes on the full
history: a narrow GROUP BY computes the measures and picks the latest event_id, then
the latest event's row is joined back for the descriptive attributes. Page views
with a repeated or NULL event_id (none seen in practice) would make that join fan
out, so they take a separate path that picks the latest row with ROW_NUMBER, as the
original model did. Ties on the latest event_time (a few hundred page views a
month) resolve to an arbitrary event, as before.

History is built in date chunks with the piano_backfill_start/end vars; see
"Backfilling the Piano page view models" in the DNS Transformations Runbook. A page view
whose events straddle a chunk boundary gets a row per chunk; the backfill script merges
them afterwards with the dedupe_page_view_fragments macro.
full_refresh=false makes dbt ignore --full-refresh here: a full refresh would
build all history in one statement, which can't finish. To rebuild, drop the
table and backfill in chunks.
*/

{#- the page.display rows in the window; rendered once per branch below rather than
    shared as a CTE, because Snowflake materialises (and spills) a CTE that is read twice -#}
{%- set page_display_events -%}
    SELECT *
    FROM {{ ref('int_piano__events_cleaned') }}
    WHERE
        event_name = 'page.display'
        AND pageview_id IS NOT NULL
        {{ piano_page_view_event_window() }}
{%- endset -%}

WITH page_display_keys AS (

    SELECT
        pageview_id,
        event_id,
        event_time,
        event_time_utc,
        page_duration
    FROM {{ ref('int_piano__events_cleaned') }}
    WHERE
        event_name = 'page.display'
        AND pageview_id IS NOT NULL
        {{ piano_page_view_event_window() }}

),

-- one row per event_id, so repeated events can be detected without a window
event_keys AS (

    SELECT
        pageview_id,
        event_id,
        COUNT(*) AS event_rows,
        MAX(page_duration) AS page_duration,
        MIN(event_time) AS first_event_time,
        MIN(event_time_utc) AS first_event_time_utc,
        MAX(event_time) AS last_event_time
    FROM page_display_keys
    GROUP BY pageview_id, event_id

),

pageview_measures AS (

    SELECT
        pageview_id,
        MAX(page_duration) AS page_duration,
        MIN(first_event_time) AS page_view_time,
        MIN(first_event_time_utc) AS page_view_time_utc,
        MAX(last_event_time) AS last_event_time,
        -- Piano's Pageviews definition counts distinct page.display event_ids,
        -- so duplicate events for one pageview_id each count
        COUNT(event_id) AS page_display_event_count,
        MAX_BY(event_id, last_event_time) AS latest_event_id,
        -- a repeated or NULL event_id would fan out the join on latest_event_id
        MAX(event_rows) > 1 OR COUNT(*) > COUNT(event_id) AS needs_row_pick
    FROM event_keys
    GROUP BY pageview_id

),

pageview_grain AS (

    -- the latest event's row, joined 1:1
    SELECT
        e.*,
        m.page_duration AS page_duration_agg,
        m.page_view_time,
        m.page_view_time_utc,
        m.last_event_time,
        m.page_display_event_count
    FROM ({{ page_display_events }}) e
    INNER JOIN pageview_measures m
        ON
            e.pageview_id = m.pageview_id
            AND e.event_id = m.latest_event_id
    WHERE NOT m.needs_row_pick

    UNION ALL

    -- page views with a repeated or NULL event_id: pick the latest row
    SELECT
        e.*,
        m.page_duration AS page_duration_agg,
        m.page_view_time,
        m.page_view_time_utc,
        m.last_event_time,
        m.page_display_event_count
    FROM ({{ page_display_events }}) e
    INNER JOIN pageview_measures m
        ON e.pageview_id = m.pageview_id
    WHERE m.needs_row_pick
    QUALIFY ROW_NUMBER() OVER (PARTITION BY e.pageview_id ORDER BY e.event_time DESC) = 1

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
    date_published,
    article_word_count,

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
    src_url,
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

    -- platform / browser
    device_platform_id,
    browser_group,
    os_version,
    app_type,
    app_name,

    -- site
    site_level2,
    site_env,
    orga_id,

    -- Composer template (populated on experience events only, so normally NULL on page.display)
    template_display_mode,
    template_closable,

    -- C1X propensity segments
    c1x_brand_relationship,
    c1x_checkout_abandonment,
    c1x_content_likely_to_convert,
    c1x_expiring_subscribers,
    c1x_likelihood_to_register,
    c1x_likelihood_to_return,
    c1x_ltc,
    c1x_lts,
    c1x_revenue_auto_optimization,
    c1x_subscription_length,
    c1x_subscription_tenure,
    c1x_visitor_frequency,
    c1x_visitor_interest,
    c1x_visitor_recency
FROM pageview_grain
