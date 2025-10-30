{{ config(materialized="view") }}

SELECT
    event_id,
    event_time,
    visit_id,
    visitor_id,
    user_id,
    device_type,
    pageview_id,
    page,
    page_title,
    page_content_type,
    event_url,
    c1x_lts
FROM {{ ref('stg_piano_events__page_views') }}