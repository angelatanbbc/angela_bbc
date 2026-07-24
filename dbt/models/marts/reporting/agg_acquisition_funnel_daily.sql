{{ config(
    materialized='table',
    tags=['subscriptions', 'piano', 'tableau'],
) }}

-- Funnel metrics for the acquisition dashboard, stored as HyperLogLog sketches so
-- distinct visitor counts can be re-aggregated across any date range or dimension
-- filter in Tableau (live connection) with:
--   RAWSQLAGG_INT("HLL_ESTIMATE(HLL_COMBINE(%1))", [exposed_visitors_hll])
-- Two row families share the table, discriminated by record_source:
--   'exposures'     - one row per date/template/app/device/os/country with the
--                     exposed-visitor sketch and exact conversion counts
--   'page_displays' - the page-display visitor sketch per date/app/device/os/
--                     country, replicated under every template_type so the
--                     exposure-rate denominator survives template cuts in
--                     Tableau; merging identical HLL sketches is exact
--                     (register-wise max), so un-cut totals are unaffected.
--                     Covers US/Canada only.
-- The two sketch columns are kept separate so HLL_COMBINE can never merge the
-- exposed and page-display visitor populations.

WITH templates AS (

    SELECT
        template_id,
        template_type
    FROM {{ ref('dim_template') }}

),

exposure_sketches AS (

    SELECT
        e.exposure_date AS date_day,
        COALESCE(t.template_type, 'Other') AS template_type,
        e.app_type_id,
        e.device_type_id,
        e.os_group_id,
        COALESCE(e.geo_country, 'Unknown') AS geo_country,
        HLL_ACCUMULATE(e.visitor_id) AS exposed_visitors_hll,
        COUNT(DISTINCT e.visitor_id) AS n_exposed_visitors
    FROM {{ ref('fact_exposures') }} e
    LEFT JOIN templates t
        ON e.template_id = t.template_id
    GROUP BY ALL

),

conversion_counts AS (

    SELECT
        c.conversion_date AS date_day,
        COALESCE(t.template_type, 'Other') AS template_type,
        c.app_type_id,
        c.device_type_id,
        c.os_group_id,
        COALESCE(c.geo_country, 'Unknown') AS geo_country,
        COUNT(DISTINCT c.conversion_id) AS n_conversions
    FROM {{ ref('fact_conversions') }} c
    LEFT JOIN templates t
        ON c.template_id = t.template_id
    GROUP BY ALL

),

exposure_rows AS (

    SELECT
        'exposures' AS record_source,
        COALESCE(e.date_day, c.date_day) AS date_day,
        COALESCE(e.template_type, c.template_type) AS template_type,
        COALESCE(e.app_type_id, c.app_type_id) AS app_type_id,
        COALESCE(e.device_type_id, c.device_type_id) AS device_type_id,
        COALESCE(e.os_group_id, c.os_group_id) AS os_group_id,
        COALESCE(e.geo_country, c.geo_country) AS geo_country,
        e.exposed_visitors_hll,
        e.n_exposed_visitors,
        NULL::BINARY AS page_visitors_hll,
        COALESCE(c.n_conversions, 0) AS n_conversions
    FROM exposure_sketches e
    FULL OUTER JOIN conversion_counts c
        ON e.date_day = c.date_day
        AND e.template_type = c.template_type
        AND e.app_type_id = c.app_type_id
        AND e.device_type_id = c.device_type_id
        AND e.os_group_id = c.os_group_id
        AND e.geo_country = c.geo_country

),

-- Every template_type the exposure rows can produce; the page-display sketch is
-- replicated under each one so any template filter still finds its denominator.
template_types AS (

    SELECT DISTINCT COALESCE(template_type, 'Other') AS template_type
    FROM templates

    UNION

    SELECT 'Other'

),

page_display_sketches AS (

    SELECT
        v.date_key AS date_day,
        v.app_type_id,
        v.device_type_id,
        v.os_group_id,
        COALESCE(g.geo_country, 'Unknown') AS geo_country,
        HLL_ACCUMULATE(v.visitor_id) AS page_visitors_hll
    FROM {{ ref('fact_visitors_daily') }} v
    LEFT JOIN {{ ref('dim_geography') }} g
        ON v.geo_id = g.geo_id
    GROUP BY
        v.date_key,
        v.app_type_id,
        v.device_type_id,
        v.os_group_id,
        COALESCE(g.geo_country, 'Unknown')

),

page_display_rows AS (

    SELECT
        'page_displays' AS record_source,
        p.date_day,
        tt.template_type,
        p.app_type_id,
        p.device_type_id,
        p.os_group_id,
        p.geo_country,
        NULL::BINARY AS exposed_visitors_hll,
        NULL::NUMBER AS n_exposed_visitors,
        p.page_visitors_hll,
        NULL::NUMBER AS n_conversions
    FROM page_display_sketches p
    CROSS JOIN template_types tt

),

unioned AS (

    SELECT
        record_source,
        date_day,
        template_type,
        app_type_id,
        device_type_id,
        os_group_id,
        geo_country,
        exposed_visitors_hll,
        n_exposed_visitors,
        page_visitors_hll,
        n_conversions
    FROM exposure_rows

    UNION ALL

    SELECT
        record_source,
        date_day,
        template_type,
        app_type_id,
        device_type_id,
        os_group_id,
        geo_country,
        exposed_visitors_hll,
        n_exposed_visitors,
        page_visitors_hll,
        n_conversions
    FROM page_display_rows

)

SELECT
    {{ dbt_utils.generate_surrogate_key([
        'u.date_day',
        'u.record_source',
        'u.template_type',
        'u.app_type_id',
        'u.device_type_id',
        'u.os_group_id',
        'u.geo_country'
    ]) }} AS funnel_day_key,
    u.record_source,
    u.date_day,
    u.template_type,
    u.app_type_id,
    at.app_type,
    u.device_type_id,
    dt.device_type,
    u.os_group_id,
    og.os_group,
    u.geo_country,
    u.exposed_visitors_hll,
    u.n_exposed_visitors,
    u.page_visitors_hll,
    u.n_conversions
FROM unioned u
LEFT JOIN {{ ref('dim_app_type') }} at
    ON u.app_type_id = at.app_type_id
LEFT JOIN {{ ref('dim_device_type') }} dt
    ON u.device_type_id = dt.device_type_id
LEFT JOIN {{ ref('dim_os_group') }} og
    ON u.os_group_id = og.os_group_id
