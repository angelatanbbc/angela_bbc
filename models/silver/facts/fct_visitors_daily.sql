{{
    config(
        materialized="incremental",
        unique_key='date_key',
        incremental_strategy='delete+insert',
        on_schema_change='sync_all_columns',
        tags=['mart','fct']
    )
}}

-- Intermediate table for subscription acquisition visitor counts
-- Pre-computes unique visitor-day combinations from page.display events
-- This table is used by all daily/weekly/monthly aggregation models to avoid
-- redundant expensive DISTINCT operations on the event-level table
--
-- Incremental runs replace whole days: every date_key in the reprocessed window
-- is deleted and rebuilt. geo_id is the visitor's modal geography for the day,
-- so it can change as late events arrive, and merging on visitor_date_key
-- (which includes geo_id) would leave the old row behind as a duplicate.
WITH multiple_geos AS (

    SELECT
        event_time::DATE AS date_key,
        site_id,
        device_platform_id,
        visitor_id,
        geo_id,
        COUNT(DISTINCT visit_id) AS n_visits,
        COUNT(*) AS n_pageviews
    FROM {{ ref('int_piano__events_cleaned') }}
    WHERE 1=1
        AND site_id IN (638824, 644938, 644937)
        AND event_time::DATE > '2025-06-25'
        AND event_name = 'page.display'
        AND geo_country IN ('United states', 'Canada')
    {% if is_incremental() %}
        AND event_time::DATE >= DATEADD(DAY, -1, (SELECT MAX(date_key) FROM {{ this }}))
    {% endif %}
    GROUP BY ALL

),

modal_geo AS (

    SELECT
        date_key,
        site_id,
        device_platform_id,
        visitor_id,
        MAX_BY(geo_id, n_pageviews) AS geo_id,
        SUM(n_visits) AS n_visits,
        SUM(n_pageviews) AS n_pageviews
    FROM multiple_geos
    GROUP BY ALL

)

SELECT
    {{ dbt_utils.generate_surrogate_key(['date_key', 'site_id', 'geo_id', 'device_platform_id', 'visitor_id']) }} AS visitor_date_key,
    date_key,
    site_id,
    device_platform_id,
    geo_id,
    visitor_id,
    n_visits,
    n_pageviews
FROM modal_geo
