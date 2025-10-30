{{ config(materialized="view") }}

SELECT
    event_id,
    event_time,
    visit_id,
    visit_time,
    visitor_id,
    user_id,
    device_type,
    pageview_id,
    page,
    page_title,
    page_content_type,
    event_url,
    c1x_lts,
    src,
    src_detail
FROM {{ source('studios_piano', 'studios_piano_events') }}
WHERE 1=1
    AND event_name = 'page.display'
    AND event_time::DATE > '2025-06-25'
    AND site_id = 638824 -- TODO: Expand to other site_ids (sport, live news, etc.)