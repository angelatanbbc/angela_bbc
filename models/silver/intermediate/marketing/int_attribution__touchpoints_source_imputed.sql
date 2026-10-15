{{
    config(
        materialized="incremental",
        incremental_strategy="delete+insert",
        unique_key="conversion_date",
        on_schema_change="fail",
        tags=["attribution", "intermediate"]
    )
}}

/*
The credited touchpoints with every touch given a source: one row per conversion x pageview_id x
touchpoint_type.

As today (int_subscription__attribution_src_corrected): a touch with no source is assigned one at
random in proportion to the known non-paid sources' credit (is_source_imputed), the generic
'Search engines' detail is split across the named engines, and owned banners become 'House Ad'.
The proportions come from the last var('attribution_imputation_window_days') days rather than the
whole table, so the model can stay incremental.
*/

{%- set batch_floor = attribution_batch_floor() %}
{%- set mix_floor = (batch_floor - modules.datetime.timedelta(days=var('attribution_imputation_window_days'))) if batch_floor else none %}

WITH batch AS (

    SELECT
        conversion_id,
        pageview_id,
        touchpoint_type,
        conversion_date,
        conversion_at,
        touchpoint_at,
        touchpoint_visitor_id,
        visit_id,
        site_id,
        identity_link_type,
        agency_resolved_from,
        ad_sk,
        campaign_tracking_sk,
        campaign_type,
        ad_format,
        piano_source,
        piano_source_detail,
        organic_source,
        organic_source_detail,
        bbc_team,
        partner,
        is_paid_touch,
        attribution_source,
        attribution_source_detail,
        position_weight,
        signup_touch_weight,
        first_touch_weight,
        last_touch_weight
    FROM {{ ref('int_attribution__touchpoints') }}
    {%- if batch_floor %}
    WHERE conversion_date >= '{{ batch_floor }}'
    {%- endif %}

),

mix_window AS (

    SELECT
        attribution_source,
        attribution_source_detail,
        position_weight
    FROM {{ ref('int_attribution__touchpoints') }}
    {%- if mix_floor %}
    WHERE conversion_date >= '{{ mix_floor }}'
    {%- endif %}

),

source_weights AS (

    SELECT
        attribution_source,
        SUM(position_weight) AS total_weight
    FROM mix_window
    WHERE
        attribution_source IS NOT NULL
        AND attribution_source != 'Paid'
    GROUP BY attribution_source

),

-- the last range is closed at 1 so no touch can fall off the end
source_ranges AS (

    SELECT
        attribution_source,
        SUM(total_weight) OVER (ORDER BY attribution_source ASC) / SUM(total_weight) OVER ()
        - total_weight / SUM(total_weight) OVER () AS lower_bound,
        IFF(
            ROW_NUMBER() OVER (ORDER BY attribution_source DESC) = 1,
            1.0,
            SUM(total_weight) OVER (ORDER BY attribution_source ASC) / SUM(total_weight) OVER ()
        ) AS upper_bound
    FROM source_weights

),

search_engine_weights AS (

    SELECT
        attribution_source_detail,
        SUM(position_weight) AS total_weight
    FROM mix_window
    WHERE
        attribution_source = 'Search engines'
        AND attribution_source_detail IS NOT NULL
        AND attribution_source_detail != 'Search engines'
    GROUP BY attribution_source_detail

),

search_engine_ranges AS (

    SELECT
        attribution_source_detail,
        SUM(total_weight) OVER (ORDER BY total_weight DESC, attribution_source_detail ASC) / SUM(total_weight) OVER ()
        - total_weight / SUM(total_weight) OVER () AS lower_bound,
        IFF(
            ROW_NUMBER() OVER (ORDER BY total_weight ASC, attribution_source_detail DESC) = 1,
            1.0,
            SUM(total_weight) OVER (ORDER BY total_weight DESC, attribution_source_detail ASC) / SUM(total_weight) OVER ()
        ) AS upper_bound
    FROM search_engine_weights

),

sourced AS (

    SELECT
        b.conversion_id,
        b.pageview_id,
        b.touchpoint_type,
        b.conversion_date,
        b.conversion_at,
        b.touchpoint_at,
        b.touchpoint_visitor_id,
        b.visit_id,
        b.site_id,
        b.identity_link_type,
        b.agency_resolved_from,
        b.ad_sk,
        b.campaign_tracking_sk,
        b.campaign_type,
        b.ad_format,
        b.piano_source,
        b.piano_source_detail,
        b.organic_source,
        b.organic_source_detail,
        b.bbc_team,
        b.partner,
        b.is_paid_touch,
        b.position_weight,
        b.signup_touch_weight,
        b.first_touch_weight,
        b.last_touch_weight,
        {%- if var('attribution_impute_unknown_sources') %}
        b.attribution_source IS NULL AS is_source_imputed,
        COALESCE(b.attribution_source, r.attribution_source) AS attribution_source,
        IFF(b.attribution_source IS NULL, r.attribution_source, b.attribution_source_detail) AS attribution_source_detail
        {%- else %}
        FALSE AS is_source_imputed,
        COALESCE(b.attribution_source, 'Unknown') AS attribution_source,
        IFF(b.attribution_source IS NULL, 'Unknown', b.attribution_source_detail) AS attribution_source_detail
        {%- endif %}
    FROM batch b
    LEFT JOIN source_ranges r
        ON b.attribution_source IS NULL
        AND UNIFORM(0::FLOAT, 1::FLOAT, HASH(b.conversion_id, b.pageview_id, b.touchpoint_type)) >= r.lower_bound
        AND UNIFORM(0::FLOAT, 1::FLOAT, HASH(b.conversion_id, b.pageview_id, b.touchpoint_type)) < r.upper_bound

),

searched AS (

    SELECT
        s.conversion_id,
        s.pageview_id,
        s.touchpoint_type,
        s.conversion_date,
        s.conversion_at,
        s.touchpoint_at,
        s.touchpoint_visitor_id,
        s.visit_id,
        s.site_id,
        s.identity_link_type,
        s.agency_resolved_from,
        s.ad_sk,
        s.campaign_tracking_sk,
        s.campaign_type,
        s.ad_format,
        s.piano_source,
        s.piano_source_detail,
        s.organic_source,
        s.organic_source_detail,
        s.bbc_team,
        s.partner,
        s.is_paid_touch,
        s.is_source_imputed,
        s.position_weight,
        s.signup_touch_weight,
        s.first_touch_weight,
        s.last_touch_weight,
        IFF(s.ad_format = 'banner' AND s.campaign_type = 'owned', 'House Ad', s.attribution_source) AS attribution_source,
        IFF(
            s.attribution_source = 'Search engines' AND s.attribution_source_detail = 'Search engines',
            COALESCE(e.attribution_source_detail, s.attribution_source_detail),
            s.attribution_source_detail
        ) AS attribution_source_detail
    FROM sourced s
    LEFT JOIN search_engine_ranges e
        ON s.attribution_source = 'Search engines'
        AND s.attribution_source_detail = 'Search engines'
        AND UNIFORM(0::FLOAT, 1::FLOAT, HASH(s.conversion_id, s.pageview_id, s.touchpoint_type, 'search')) >= e.lower_bound
        AND UNIFORM(0::FLOAT, 1::FLOAT, HASH(s.conversion_id, s.pageview_id, s.touchpoint_type, 'search')) < e.upper_bound

)

SELECT
    conversion_id,
    pageview_id,
    touchpoint_type,
    conversion_date,
    conversion_at,
    touchpoint_at,
    touchpoint_visitor_id,
    visit_id,
    site_id,
    identity_link_type,
    agency_resolved_from,
    ad_sk,
    {{ dbt_utils.generate_surrogate_key([
        'attribution_source', 'attribution_source_detail', 'piano_source', 'piano_source_detail',
        'organic_source', 'organic_source_detail', 'bbc_team', 'partner'
    ]) }} AS channel_sk,
    campaign_tracking_sk,
    attribution_source,
    attribution_source_detail,
    piano_source,
    piano_source_detail,
    organic_source,
    organic_source_detail,
    bbc_team,
    partner,
    is_paid_touch,
    is_source_imputed,
    position_weight,
    signup_touch_weight,
    first_touch_weight,
    last_touch_weight
FROM searched
