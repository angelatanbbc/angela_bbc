{{ config(
    materialized='incremental',
    unique_key='pageview_id',
    incremental_strategy='merge',
    on_schema_change='sync_all_columns'
) }}


-- Get page view events from collected by Piano Analytics
WITH web_page_views AS (

    SELECT
        pageview_id,
        event_id,
        event_time,
        visitor_id,
        visit_id,
        user_id,
        user_first_party_id,
        src,
        src_detail,
        src_url,
        app_type_id,
        device_type_id,
        os_group_id,
        event_collection_platform,
        page,
        page_title,
        page_content_type,
        content_type,
        content_id,
        content_section,
        content_topic,
        content_pillar,
        date_published,
        url,
        event_url,
        event_url_domain,
        event_url_full,
        geo_id,
        geo_country,
        geo_region,
        geo_city,
        c1x_brand_relationship
    FROM {{ ref('stg_piano__analytics_events') }}
    WHERE
        app_type_id = MD5('Web')
        AND geo_country IN ('United states', 'Canada')
        AND pageview_id IS NOT NULL
        {% if is_incremental() %}
            AND event_time::DATE >= DATEADD(DAY, -1, (SELECT MAX(pageview_time)::DATE FROM {{ this }}))
        {% endif %}
    -- In case there are multiple page.display events for the same pageview_id, take the earliest one
    QUALIFY ROW_NUMBER() OVER (PARTITION BY pageview_id ORDER BY event_time) = 1

),

app_page_views AS (

    SELECT
        NULL AS pageview_id,
        event_id,
        event_time,
        visitor_id,
        visit_id,
        user_id,
        user_first_party_id,
        src,
        src_detail,
        src_url,
        app_type_id,
        device_type_id,
        os_group_id,
        event_collection_platform,
        page,
        page_title,
        page_content_type,
        content_type,
        content_id,
        content_section,
        content_topic,
        content_pillar,
        date_published,
        url,
        event_url,
        event_url_domain,
        event_url_full,
        geo_id,
        geo_country,
        geo_region,
        geo_city,
        c1x_brand_relationship
    FROM {{ ref('stg_piano__analytics_events') }}
    WHERE
        app_type_id = MD5('Mobile App')
        AND geo_country IN ('United states', 'Canada')
        AND event_id IS NOT NULL
        {% if is_incremental() %}
            AND event_time::DATE >= DATEADD(DAY, -1, (SELECT MAX(pageview_time)::DATE FROM {{ this }}))
        {% endif %}

),

unioned_page_views AS (

    SELECT *
    FROM web_page_views

    UNION ALL
    
    SELECT *
    FROM app_page_views

)

SELECT
    pageview_id,
    event_time AS pageview_time,
    event_time::DATE AS pageview_date,

    -- IDs
    visitor_id,
    visit_id,
    user_id,
    user_first_party_id,

    -- Acquisition / visit source
    src,
    src_detail,
    src_url,

    -- Device / App
    event_collection_platform,
    app_type_id,
    device_type_id,
    os_group_id,

    -- Page Info
    page,
    page_title,
    page_content_type,
    content_type,
    content_id,
    content_section,
    content_topic,
    content_pillar,
    date_published,
    url AS content_url,
    event_url AS page_url,
    event_url_domain AS page_url_domain,
    event_url_full AS page_url_full,

    -- Geography
    geo_id,
    IFNULL(geo_country, 'Unknown') AS geo_country,
    IFNULL(geo_region, 'Unknown') AS geo_region,
    IFNULL(geo_city, 'Unknown') AS geo_city,

    c1x_brand_relationship AS pageview_c1x_brand_relationship,
    c1x_brand_relationship IN ('Paid trial users', 'Subscribers') AS is_paid_trial_or_subscriber

FROM unioned_page_views
