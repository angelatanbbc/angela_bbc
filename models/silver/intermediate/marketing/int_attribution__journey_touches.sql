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
Every touch in each purchase's journey: one row per conversion x pageview_id x touchpoint_type.

A touch is a page view on any of the buyer's cookies inside the journey window, or the purchase
itself. The purchase is a touch only when Piano recorded it on the checkout cookie, as in today's
model. Corrections, each behind a var: the return from account.bbc.com after sign-in is not a touch,
and a visit that lost its agency tag takes it from its Meta ad (dim_ad), else from an 8ms_ / dbs_
campaign name on a Facebook or Instagram visit (agency_resolved_from).
*/

{%- set batch_floor = attribution_batch_floor() %}
{%- set lookback_days = var('attribution_lookback_days') %}
{%- set columns = attribution_touch_columns() %}

WITH conversions AS (

    SELECT
        conversion_id,
        conversion_date,
        conversion_at,
        previous_conversion_at,
        checkout_pageview_id,
        checkout_visitor_id,
        conversion_visitor_id,
        promo_code,
        {%- for column in columns %}
        {{ column }}{{ ',' if not loop.last }}
        {%- endfor %}
    FROM {{ ref('int_attribution__conversions') }}
    {%- if batch_floor %}
    WHERE conversion_date >= '{{ batch_floor }}'
    {%- endif %}

),

identities AS (

    SELECT
        conversion_id,
        visitor_id,
        identity_link_type
    FROM {{ ref('int_attribution__journey_identities') }}
    {%- if batch_floor %}
    WHERE conversion_date >= '{{ batch_floor }}'
    {%- endif %}

),

page_view_touches AS (

    SELECT
        c.conversion_id,
        c.conversion_date,
        c.conversion_at,
        pv.pageview_id,
        'page_view' AS touchpoint_type,
        pv.page_view_time AS touchpoint_at,
        pv.visitor_id AS touchpoint_visitor_id,
        i.identity_link_type,
        NULL AS promo_code,
        SPLIT_PART(pv.src_referrer_url, '/', 3) AS referrer_host,
        FALSE AS is_off_cookie_purchase,
        {%- for column in columns %}
        pv.{{ column }}{{ ',' if not loop.last }}
        {%- endfor %}
    FROM identities i
    JOIN conversions c ON i.conversion_id = c.conversion_id
    JOIN {{ ref('int_piano__page_views') }} pv
        ON i.visitor_id = pv.visitor_id
        AND pv.page_view_time <= c.conversion_at
        AND DATEDIFF(DAY, pv.page_view_time, c.conversion_at) <= {{ lookback_days }}
        AND (c.previous_conversion_at IS NULL OR pv.page_view_time > c.previous_conversion_at)
    WHERE
        TRUE
        {%- if batch_floor %}
        AND pv.page_view_time >= '{{ (batch_floor - modules.datetime.timedelta(days=lookback_days + 1)).isoformat() }}'
        {%- endif %}
        {%- if var('attribution_site_scope') %}
        AND pv.site_id IN (SELECT s.site_id FROM {{ ref('subscription_sites') }} s)
        {%- endif %}

),

purchase_touches AS (

    SELECT
        conversion_id,
        conversion_date,
        conversion_at,
        checkout_pageview_id AS pageview_id,
        'conversion' AS touchpoint_type,
        conversion_at AS touchpoint_at,
        conversion_visitor_id AS touchpoint_visitor_id,
        'checkout_cookie' AS identity_link_type,
        promo_code,
        NULL AS referrer_host,
        conversion_visitor_id != checkout_visitor_id AS is_off_cookie_purchase,
        {%- for column in columns %}
        {{ column }}{{ ',' if not loop.last }}
        {%- endfor %}
    FROM conversions

),

all_touches AS (

    {%- for touch_cte in ['page_view_touches', 'purchase_touches'] %}
    SELECT
        conversion_id,
        conversion_date,
        conversion_at,
        pageview_id,
        touchpoint_type,
        touchpoint_at,
        touchpoint_visitor_id,
        identity_link_type,
        promo_code,
        referrer_host,
        is_off_cookie_purchase,
        {%- for column in columns %}
        {{ column }}{{ ',' if not loop.last }}
        {%- endfor %}
    FROM {{ touch_cte }}
    {%- if not loop.last %}

    UNION ALL

    {%- endif %}
    {%- endfor %}

),

ads AS (

    SELECT
        a.platform,
        a.ad_id,
        a.ad_sk,
        LOWER(a.bbc_team) AS bbc_team,
        pa.bbc_team_raw IS NOT NULL AS is_paid_agency
    FROM {{ ref('dim_ad') }} a
    LEFT JOIN {{ ref('bbc_team_agencies') }} pa
        ON LOWER(a.bbc_team) = pa.bbc_team_raw
        AND pa.is_paid_media
    WHERE a.platform != 'unknown'
    -- an id reported by two platforms resolves to its Meta ad
    QUALIFY ROW_NUMBER() OVER (PARTITION BY a.ad_id ORDER BY IFF(a.platform = 'meta', 0, 1), a.platform) = 1

),

resolved AS (

    SELECT
        t.conversion_id,
        t.conversion_date,
        t.conversion_at,
        t.pageview_id,
        t.touchpoint_type,
        t.touchpoint_at,
        t.touchpoint_visitor_id,
        t.visit_id,
        t.site_id,
        t.identity_link_type,
        t.promo_code,
        COALESCE(t.touchpoint_type = 'page_view' AND t.referrer_host = 'account.bbc.com', FALSE) AS is_signin_return,
        t.is_off_cookie_purchase,
        t.src,
        -- Piano's own checkout is not a referrer
        IFF(t.src_detail = 'buy-eu.piano.io', NULL, t.src_detail) AS src_detail,
        t.src_organic,
        t.src_organic_detail,
        t.src_ptr_name,
        t.url_at_bbc_team,
        t.url_at_objective,
        t.url_at_ptr_name,
        CASE
            WHEN NULLIF(t.src_bbc_team, '') IS NOT NULL OR NULLIF(t.url_at_bbc_team, '') IS NOT NULL
                THEN t.src_bbc_team
            {%- if var('attribution_fill_agency') %}
            WHEN a.platform = 'meta' AND a.is_paid_agency THEN a.bbc_team
            WHEN
                LOWER(COALESCE(t.src_ptr_name, '')) IN ('facebook', 'instagram', 'fb', 'ig')
                AND LOWER(COALESCE(t.src_detail, '') || ' ' || COALESCE(t.src_campaign, '')) LIKE '%dbs^_%' ESCAPE '^'
                THEN 'dbs'
            WHEN
                LOWER(COALESCE(t.src_ptr_name, '')) IN ('facebook', 'instagram', 'fb', 'ig')
                AND LOWER(COALESCE(t.src_detail, '') || ' ' || COALESCE(t.src_campaign, '')) LIKE '%8ms^_%' ESCAPE '^'
                THEN '8ms'
            {%- endif %}
            ELSE t.src_bbc_team
        END AS src_bbc_team,
        CASE
            WHEN NULLIF(t.src_bbc_team, '') IS NOT NULL OR NULLIF(t.url_at_bbc_team, '') IS NOT NULL
                THEN 'visit_tag'
            {%- if var('attribution_fill_agency') %}
            WHEN a.platform = 'meta' AND a.is_paid_agency THEN 'ad_id'
            WHEN
                LOWER(COALESCE(t.src_ptr_name, '')) IN ('facebook', 'instagram', 'fb', 'ig')
                AND LOWER(COALESCE(t.src_detail, '') || ' ' || COALESCE(t.src_campaign, '')) LIKE ANY ('%dbs^_%', '%8ms^_%') ESCAPE '^'
                THEN 'campaign_name'
            {%- endif %}
            ELSE 'none'
        END AS agency_resolved_from,
        a.ad_sk,
        -- campaign tags: Piano's column first, the landing URL's tag as the fallback
        COALESCE(NULLIF(t.src_campaign, ''), NULLIF(t.url_at_campaign, '')) AS campaign,
        COALESCE(NULLIF(t.src_adset_name, ''), NULLIF(t.url_at_adset_name, '')) AS ad_set_name,
        COALESCE(NULLIF(t.src_adset_id, ''), NULLIF(t.url_at_adset_id, '')) AS ad_set_id,
        COALESCE(NULLIF(t.src_creative_id, ''), NULLIF(t.url_at_creative_id, '')) AS creative_id,
        COALESCE(NULLIF(t.url_at_creation, ''), NULLIF(t.src_creation, '')) AS creation,
        COALESCE(NULLIF(t.src_objective, ''), NULLIF(t.url_at_objective, '')) AS objective,
        COALESCE(NULLIF(t.src_medium, ''), NULLIF(t.url_at_medium, '')) AS medium,
        COALESCE(NULLIF(t.src_sl_term, ''), NULLIF(t.url_at_keyword, '')) AS keyword,
        NULLIF(t.url_at_matchtype, '') AS match_type,
        NULLIF(t.src_campaign_type, '') AS campaign_type,
        NULLIF(t.src_format, '') AS ad_format,
        NULLIF(t.url_at_link_origin, '') AS link_origin,
        NULLIF(t.url_at_campaign_name, '') AS at_campaign_name,
        {{ generate_geo_id('t.geo_country', 't.geo_region') }} AS geo_id,
        t.device_platform_id,
        t.geo_country,
        t.geo_region,
        t.browser_group,
        t.content_id,
        t.content_pillar,
        t.content_section,
        t.content_type
    FROM all_touches t
    LEFT JOIN ads a ON COALESCE(NULLIF(t.src_creative_id, ''), NULLIF(t.url_at_creative_id, '')) = a.ad_id

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
    IFF(
        COALESCE(
            campaign, ad_set_name, ad_set_id, creative_id, creation, objective, medium,
            keyword, match_type, campaign_type, ad_format, link_origin, at_campaign_name
        ) IS NULL,
        {{ dbt_utils.generate_surrogate_key(["'none'"]) }},
        {{ dbt_utils.generate_surrogate_key([
            'campaign', 'ad_set_name', 'ad_set_id', 'creative_id', 'creation', 'objective', 'medium',
            'keyword', 'match_type', 'campaign_type', 'ad_format', 'link_origin', 'at_campaign_name'
        ]) }}
    ) AS campaign_tracking_sk,
    geo_id,
    device_platform_id,
    promo_code,
    src,
    src_detail,
    src_organic,
    src_organic_detail,
    src_bbc_team,
    src_ptr_name,
    url_at_bbc_team,
    url_at_objective,
    url_at_ptr_name,
    campaign,
    ad_set_name,
    ad_set_id,
    creative_id,
    creation,
    objective,
    medium,
    keyword,
    match_type,
    campaign_type,
    ad_format,
    link_origin,
    at_campaign_name,
    geo_country,
    geo_region,
    browser_group,
    content_id,
    content_pillar,
    content_section,
    content_type
FROM resolved
{%- set not_a_touch = 'is_off_cookie_purchase OR is_signin_return' if var('attribution_skip_signin_return') else 'is_off_cookie_purchase' %}
-- an off-cookie purchase and (corrected logic) the sign-in return are kept only when the journey has nothing else
QUALIFY
    NOT ({{ not_a_touch }})
    OR COUNT_IF(NOT ({{ not_a_touch }})) OVER (PARTITION BY conversion_id) = 0
