{{
    config(
        materialized="incremental",
        incremental_strategy="delete+insert",
        unique_key="conversion_date",
        on_schema_change="fail",
        tags=["fct", "attribution"]
    )
}}

{%- set batch_floor = attribution_batch_floor() %}

WITH touchpoints AS (

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
        channel_sk,
        campaign_tracking_sk,
        is_paid_touch,
        is_source_imputed,
        position_weight,
        signup_touch_weight,
        first_touch_weight,
        last_touch_weight
    FROM {{ ref('int_attribution__touchpoints_source_imputed') }}
    {%- if batch_floor %}
    WHERE conversion_date >= '{{ batch_floor }}'
    {%- endif %}

),

touches AS (

    SELECT
        conversion_id,
        pageview_id,
        touchpoint_type,
        geo_id,
        device_type_id,
        os_group_id,
        geo_country,
        geo_region,
        browser_group,
        content_id,
        content_pillar,
        content_section,
        content_type
    FROM {{ ref('int_attribution__journey_touches') }}
    {%- if batch_floor %}
    WHERE conversion_date >= '{{ batch_floor }}'
    {%- endif %}

),

conversions AS (

    SELECT
        conversion_id,
        subscription_id,
        checkout_visitor_id,
        billing_period,
        is_lookback_complete
    FROM {{ ref('int_attribution__conversions') }}

)

SELECT
    -- keys
    {{ dbt_utils.generate_surrogate_key(['t.conversion_id', 't.pageview_id', 't.touchpoint_type']) }} AS attribution_touchpoint_sk,
    t.conversion_id,
    c.subscription_id,
    t.channel_sk,
    t.campaign_tracking_sk,
    t.ad_sk,
    j.geo_id,
    j.device_type_id,
    j.os_group_id,
    c.checkout_visitor_id AS visitor_id,
    t.touchpoint_visitor_id,
    t.visit_id,
    t.pageview_id,
    t.site_id,
    j.content_id,

    -- dates
    t.touchpoint_at::DATE AS touchpoint_date,
    t.touchpoint_at,
    t.conversion_date,
    t.conversion_at,

    -- attributes
    t.touchpoint_type,
    c.billing_period,
    t.identity_link_type,
    t.agency_resolved_from,
    t.is_paid_touch,
    t.is_source_imputed,
    c.is_lookback_complete,
    j.geo_country,
    j.geo_region,
    j.browser_group,
    j.content_pillar,
    j.content_section,
    j.content_type,

    -- measures
    t.position_weight::NUMBER(18, 6) AS position_weight,
    t.signup_touch_weight::NUMBER(18, 6) AS signup_touch_weight,
    t.first_touch_weight::NUMBER(18, 6) AS first_touch_weight,
    t.last_touch_weight::NUMBER(18, 6) AS last_touch_weight
FROM touchpoints t
JOIN conversions c ON t.conversion_id = c.conversion_id
JOIN touches j
    ON t.conversion_id = j.conversion_id
    AND t.pageview_id = j.pageview_id
    AND t.touchpoint_type = j.touchpoint_type
