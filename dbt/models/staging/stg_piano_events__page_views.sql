{{ config(materialized="view") }}

SELECT
    event_id,
    event_time,
    
    -- Geographical Information
    geo_country,
    geo_region,
    geo_city,

    -- Visit Information
    visitor_id,
    visit_id,
    visit_time,
    visit_time_utc,
    visit_bounce,
    visit_converted,
    visit_duration,
    visit_entry_aisle1,
    visit_entry_aisle2,
    visit_entry_aisle3,
    visit_entry_aisle4,
    visit_entry_aisle5,
    visit_entry_aisle6,
    visit_entry_site_level2,
    visit_entrypage,
    visit_entrypage_chapter1,
    visit_entrypage_chapter2,
    visit_entrypage_chapter3,
    visit_entrypage_dynamic_name,
    visit_entrypage_full_name,
    visit_exit_site_level2,
    visit_exitpage,
    visit_exitpage_chapter1,
    visit_exitpage_chapter2,
    visit_exitpage_chapter3,
    visit_exitpage_full_name,
    visit_implication_degree,
    visit_page_views,
    visit_sales,
    src,
    src_detail,

    -- Page View Specific Information
    user_id,
    device_type,
    pageview_id,
    page,
    page_title,
    page_content_type,
    event_url,
    c1x_lts

FROM {{ source('studios_piano', 'studios_piano_events') }}
WHERE 1=1
    AND event_name = 'page.display'
    AND event_time::DATE > '2025-06-25'
    AND site_id = 638824 -- TODO: Expand to other site_ids (sport, live news, etc.)