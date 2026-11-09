{{
    config(
        materialized="incremental",
        incremental_strategy="merge",
        unique_key="event_id",
        on_schema_change="fail",
        tags=["newsletter", "intermediate"]
    )
}}

/*
The newsletters page's events: one row per page.display of the page and per newsletter.subscribe
fired on it, on var('marketing_site_ids'). The page never sets a pageview_id, so the newsletter
models are keyed on the event and the visit, not the page view.
Incremental: rereads the events from the day before the latest one loaded; the first build starts at
var('newsletter_start_date').
*/

{%- set floor = incremental_date_floor('event_time') %}

WITH events AS (

    SELECT
        event_id,
        event_name,
        event_time,
        site_id,
        visit_id,
        visitor_id,
        IFF(user_id ILIKE 'unidentified%', NULL, NULLIF(user_id, '')) AS user_id,
        url,
        src,
        src_detail,
        src_format,
        src_medium,
        src_campaign,
        src_bbc_team,
        src_ptr_name,
        newsletter_title,
        geo_id,
        geo_country,
        device_platform_id,
        browser_group
    FROM {{ ref('int_piano__events_cleaned') }}
    WHERE
        page = 'newsletters.page'
        AND site_id IN ({{ var('marketing_site_ids') | join(', ') }})
        AND event_name IN ('page.display', 'newsletter.subscribe')
        AND event_time >= '{{ floor if floor else var("newsletter_start_date") }}'

)

SELECT
    event_id,
    event_name,
    event_time,
    event_time::DATE AS event_date,
    site_id,
    visit_id,
    visitor_id,
    user_id,
    -- source and tag values arrive in mixed case (Onsite / onsite, Module / module), so they are lower-cased
    NULLIF(LOWER(TRIM(src)), '') AS src,
    NULLIF(LOWER(TRIM(src_detail)), '') AS src_detail,
    NULLIF(LOWER(TRIM(src_format)), '') AS src_format,
    NULLIF(LOWER(TRIM(src_medium)), '') AS src_medium,
    NULLIF(LOWER(TRIM(src_campaign)), '') AS src_campaign,
    src_bbc_team,
    NULLIF(LOWER(TRIM(src_ptr_name)), '') AS src_ptr_name,
    -- the page's tags are joined with '$' (...page$at_link_origin=homepage$at_format=...)
    NULLIF(LOWER(TRIM(REGEXP_SUBSTR(url, '[$?&;]at_link_origin=([^$&#]+)', 1, 1, 'e', 1))), '') AS at_link_origin,
    NULLIF(LOWER(TRIM(REGEXP_SUBSTR(url, '[$?&;]at_format=([^$&#]+)', 1, 1, 'e', 1))), '') AS at_format,
    newsletter_title,
    geo_id,
    geo_country,
    device_platform_id,
    browser_group
FROM events
QUALIFY ROW_NUMBER() OVER (PARTITION BY event_id ORDER BY event_time DESC) = 1
