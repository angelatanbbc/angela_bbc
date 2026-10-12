{{
    config(
        materialized="view",
        tags=["piano", "intermediate", "joseph.iles@bbc.com"]
    )
}}

/*
Single cleaning pass over the raw Piano events table.

At production scale the events table is tens of billions of rows, so this model
exists to do the expensive work exactly once: filter to the event families used
for page view analysis, prune ~260 columns down to the curated set, and normalize
dirty dimension values. Every downstream rollup reads from here instead of
re-scanning staging.

Incremental* (append-only, same pattern as the staging model): each run processes
only events newer than the max event_time already loaded. Events are immutable,
so no merge key is needed; late-arriving events with an event_time at or before
the watermark are picked up by a --full-refresh.

Event families kept:
- page.display                  page views
- page.scroll                   scroll depth (0-1 fraction, carried only on this event)
- click.*                       click actions
- viewability.select            click-type event (client metric definition)
- subscription.select           click-type event (client metric definition)
- ad.click                      click-type event (client metric definition)
- internal_search_result.click  click-type event (client metric definition)
- av.ad.click                   click-type event (client metric definition)
- newsletter.subscribe          click-like event with its own definition
- experience.interaction        click-like event with its own definition
- ad.impression                 monetized ad impressions (only carrier of ad_revenue)
- publisher.display             publisher/onsite ad impressions
- widget.impression             native ad widget impressions
exclusion.* events are Piano's own reporting exclusions and are deliberately not matched.

* NOTE: intended to be incremental, but using a view for now because there are petabytes
of data and the incremental logic is not yet implemented.

*/

SELECT
    -- event identifiers
    event_id,
    event_name,
    pageview_id,
    visit_id,
    visitor_id,
    user_id,
    site_id,
    content_id,

    -- timestamps
    event_time,
    event_time_utc,
    visit_time,
    visit_time_utc,

    -- event-level measures
    page_duration,
    event_duration,
    scroll_depth,
    ad_revenue,

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
    src_referrer_url,
    utm_source,
    utm_medium,
    utm_campaign,
    utm_content,
    utm_term,

    -- geography
    geo_continent,
    geo_country,
    geo_country_code_alpha2,
    geo_region,
    geo_city,
    geo_metro,

    -- device / browser / OS (normalized: consistent casing, blanks to 'Unknown')
    COALESCE(NULLIF(TRIM(device_type), ''), 'Unknown') AS device_type,
    CASE LOWER(TRIM(os_group))
        WHEN 'ios' THEN 'iOS'
        WHEN 'ipados' THEN 'iPadOS'
        WHEN 'android' THEN 'Android'
        WHEN 'windows' THEN 'Windows'
        WHEN 'macos' THEN 'macOS'
        WHEN 'linux' THEN 'Linux'
        WHEN 'chrome os' THEN 'Chrome OS'
        WHEN '' THEN 'Unknown'
        ELSE COALESCE(os_group, 'Unknown')
    END AS os_group,
    COALESCE(NULLIF(TRIM(browser_group), ''), 'Unknown') AS browser_group,

    -- site
    site_level2,
    site_env,
    orga_id

FROM {{ ref('stg_piano__studios_events') }}
WHERE
    pageview_id IS NOT NULL
    AND (
        event_name IN (
            'page.display',
            'page.scroll',
            'viewability.select',
            'subscription.select',
            'ad.click',
            'internal_search_result.click',
            'av.ad.click',
            'newsletter.subscribe',
            'experience.interaction',
            'ad.impression',
            'publisher.display',
            'widget.impression'
        )
        OR event_name LIKE 'click.%'
    )

    {% if is_incremental() %}
        AND event_time > (SELECT max(event_time) FROM {{ this }})
    {% endif %}
