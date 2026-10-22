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
The touches that get credit, and how much: one row per conversion x pageview_id x touchpoint_type.
It keeps only some of the touches in int_attribution__journey_touches.

For each touch it decides:
- whether it is kept (the keep rules)
- whether it is paid (DBS / 8MS) and its attribution source
- its credit under four models: position (reported), sign-up touch, first touch and last touch

These rules are copied step for step from the old model (archive/old_attribution/int_subscription__attribution.sql).
Differences:
- journeys are grouped by purchase (conversion_id), not by cookie and sign-up time
- the sign-up touch weight is counted per purchase (today: per cookie); when the purchase is not a
  touch, the last touch takes the purchase's 40%, so it always sums to 1 (today it can sum to 0.4)
- touches at the same time are ordered by touchpoint_type then pageview_id, so a rebuild gives the same credit
- a promo-code journey's position weights are scaled to add up to 1 (today they add up to more than 1 when a
  paid touch is not the first or last)
*/

{%- set batch_floor = attribution_batch_floor() %}

WITH touches AS (

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
        promo_code,
        src_organic,
        src_organic_detail,
        campaign_type,
        ad_format,
        -- an empty Piano source falls back to the landing URL's tags
        COALESCE(NULLIF(src, ''), NULLIF(url_at_bbc_team, ''), NULLIF(url_at_objective, ''), NULLIF(url_at_ptr_name, '')) AS src,
        COALESCE(NULLIF(src_detail, ''), NULLIF(url_at_bbc_team, ''), NULLIF(url_at_objective, ''), NULLIF(url_at_ptr_name, '')) AS src_detail,
        COALESCE(NULLIF(src_bbc_team, ''), NULLIF(url_at_bbc_team, '')) AS bbc_team,
        COALESCE(NULLIF(src_ptr_name, ''), NULLIF(url_at_ptr_name, '')) AS partner,
        LOWER(src_bbc_team) AS visit_team,
        LOWER(url_at_bbc_team) AS url_team
    FROM {{ ref('int_attribution__journey_touches') }}
    {%- if batch_floor %}
    WHERE conversion_date >= '{{ batch_floor }}'
    {%- endif %}

),

paid_agencies AS (

    SELECT bbc_team_raw
    FROM {{ ref('bbc_team_agencies') }}
    WHERE is_paid_media

),

numbered AS (

    SELECT
        t.conversion_id,
        t.pageview_id,
        t.touchpoint_type,
        t.conversion_date,
        t.conversion_at,
        t.touchpoint_at,
        t.touchpoint_visitor_id,
        t.visit_id,
        t.site_id,
        t.identity_link_type,
        t.agency_resolved_from,
        t.ad_sk,
        t.campaign_tracking_sk,
        t.promo_code,
        t.src_organic,
        t.src_organic_detail,
        t.campaign_type,
        t.ad_format,
        t.src,
        t.src_detail,
        t.bbc_team,
        t.partner,
        IFF(t.src = 'paid' OR pv.bbc_team_raw IS NOT NULL OR pu.bbc_team_raw IS NOT NULL, 1, 0) AS is_paid_event,
        ROW_NUMBER() OVER (
            PARTITION BY t.conversion_id, t.touchpoint_visitor_id, t.visit_id, t.touchpoint_type
            ORDER BY t.touchpoint_at, t.pageview_id
        ) AS visit_number
    FROM touches t
    LEFT JOIN paid_agencies pv ON t.visit_team = pv.bbc_team_raw
    LEFT JOIN paid_agencies pu ON t.url_team = pu.bbc_team_raw

),

bounded AS (

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
        promo_code,
        src_organic,
        src_organic_detail,
        campaign_type,
        ad_format,
        src,
        src_detail,
        bbc_team,
        partner,
        is_paid_event,
        visit_number,
        COALESCE(
            MAX(IFF(touchpoint_at < conversion_at AND visit_number = 1, touchpoint_at, NULL))
                OVER (PARTITION BY conversion_id),
            conversion_at
        ) AS last_event,
        COALESCE(MIN(touchpoint_at) OVER (PARTITION BY conversion_id), conversion_at) AS first_event
    FROM numbered

),

-- the purchase, the first touch, the last touch before the purchase, the first touch of each day,
-- the first touch of each paid visit and owned House Ad banners; second touches of a visit are dropped
kept AS (

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
        promo_code,
        src_organic,
        src_organic_detail,
        campaign_type,
        ad_format,
        src,
        src_detail,
        bbc_team,
        partner,
        is_paid_event,
        visit_number,
        last_event
    FROM bounded
    WHERE
        touchpoint_at <= conversion_at
        AND visit_number != 2
    QUALIFY
        touchpoint_at = conversion_at
        OR (touchpoint_at = first_event AND visit_number = 1)
        OR (touchpoint_at = last_event AND visit_number = 1)
        OR (touchpoint_at = MIN(touchpoint_at) OVER (PARTITION BY conversion_id, touchpoint_at::DATE) AND visit_number = 1)
        OR (is_paid_event = 1 AND visit_number = 1)
        OR (ad_format = 'banner' AND campaign_type = 'owned')

),

journey_stats AS (

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
        promo_code,
        src_organic,
        src_organic_detail,
        campaign_type,
        ad_format,
        src,
        src_detail,
        bbc_team,
        partner,
        is_paid_event,
        last_event,
        -- the first touch among the kept ones, as today
        COALESCE(MIN(touchpoint_at) OVER (PARTITION BY conversion_id), conversion_at) AS first_event,
        COUNT(*) OVER (PARTITION BY conversion_id) AS total_events,
        MAX(IFF(touchpoint_type = 'conversion' AND promo_code IS NOT NULL, 1, 0)) OVER (PARTITION BY conversion_id) AS has_promo,
        MAX(IFF(touchpoint_type = 'conversion', promo_code, NULL)) OVER (PARTITION BY conversion_id) AS promo_code_from_conversion,
        MIN(IFF(is_paid_event = 1, touchpoint_at, NULL)) OVER (PARTITION BY conversion_id) AS first_paid_event,
        MAX(IFF(is_paid_event = 1, touchpoint_at, NULL)) OVER (PARTITION BY conversion_id) AS last_paid_event,
        -- the sign-up touch: the purchase, else the last touch when the purchase is not a touch
        MAX(touchpoint_at) OVER (PARTITION BY conversion_id) AS signup_at,
        ROW_NUMBER() OVER (
            PARTITION BY conversion_id
            ORDER BY touchpoint_at ASC, touchpoint_type DESC, pageview_id ASC
        ) AS rn,
        ROW_NUMBER() OVER (
            PARTITION BY conversion_id, IFF(is_paid_event = 1, 1, NULL)
            ORDER BY touchpoint_at ASC, touchpoint_type DESC, pageview_id ASC
        ) AS paid_rn,
        SUM(is_paid_event) OVER (PARTITION BY conversion_id) AS total_paid_events
    FROM kept

),

positioned AS (

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
        promo_code,
        src_organic,
        src_organic_detail,
        campaign_type,
        ad_format,
        src,
        src_detail,
        bbc_team,
        partner,
        is_paid_event,
        first_event,
        last_event,
        total_events,
        has_promo,
        promo_code_from_conversion,
        first_paid_event,
        last_paid_event,
        signup_at,
        total_paid_events,
        CASE
            WHEN rn = 1 THEN 'first'
            WHEN rn = total_events THEN 'last'
            ELSE 'middle'
        END AS position_role,
        is_paid_event = 1 AND paid_rn = 1 AS is_first_paid,
        is_paid_event = 1 AND paid_rn = total_paid_events AS is_last_paid,
        SUM(
            IFF(
                rn != 1
                AND rn != total_events
                AND NOT (is_paid_event = 1 AND paid_rn = 1)
                AND NOT (is_paid_event = 1 AND paid_rn = total_paid_events),
                1,
                0
            )
        ) OVER (PARTITION BY conversion_id) AS eligible_middle_count
    FROM journey_stats

),

weighted AS (

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
        src_organic,
        src_organic_detail,
        campaign_type,
        ad_format,
        src,
        src_detail,
        bbc_team,
        partner,
        is_paid_event,
        has_promo,
        -- promo-code journeys are credited to the code; short same-day ones in full
        CASE
            WHEN total_events < 4 AND first_event::DATE = last_event::DATE AND promo_code_from_conversion IS NOT NULL
                THEN promo_code_from_conversion || ' Promo code'
            WHEN promo_code IS NOT NULL THEN promo_code || ' Promo code'
            ELSE src
        END AS attribution_source_unpaid,
        CASE
            WHEN total_events < 4 AND first_event::DATE = last_event::DATE AND promo_code_from_conversion IS NOT NULL
                THEN promo_code_from_conversion || ' Promo code'
            WHEN promo_code IS NOT NULL THEN promo_code || ' Promo code'
            ELSE src_detail
        END AS attribution_source_detail_unpaid,
        CASE
            WHEN has_promo = 1 THEN
                CASE
                    WHEN total_events = 1 THEN 1.0
                    WHEN total_events = 2 THEN 0.5
                    WHEN total_events = 3 THEN 1 / 3
                    WHEN touchpoint_at = first_event THEN 0.3
                    WHEN touchpoint_at = first_paid_event THEN 0.3
                    WHEN touchpoint_at = last_event THEN 0.3
                    WHEN touchpoint_at = last_paid_event THEN 0.3
                    WHEN touchpoint_type = 'conversion' AND promo_code IS NOT NULL THEN 0.3
                    ELSE 0.1 / NULLIF(total_events - 3, 0)
                END
            WHEN total_events = 1 THEN 1.0
            WHEN total_events = 2 THEN 0.5
            WHEN total_events = 3 THEN 1.0 / 3
            ELSE
                IFF(position_role = 'first', 0.2, 0)
                + IFF(position_role = 'last', 0.2, 0)
                + CASE
                    WHEN total_paid_events = 0 AND position_role = 'first' THEN 0.2
                    WHEN total_paid_events > 0 AND is_first_paid THEN 0.2
                    ELSE 0
                END
                + CASE
                    WHEN total_paid_events = 0 AND position_role = 'last' THEN 0.2
                    WHEN total_paid_events > 0 AND is_last_paid THEN 0.2
                    ELSE 0
                END
                + CASE
                    WHEN eligible_middle_count > 0 AND position_role = 'middle' AND NOT is_first_paid AND NOT is_last_paid
                        THEN 0.2 / eligible_middle_count
                    WHEN eligible_middle_count = 0 AND position_role = 'last' THEN 0.2
                    ELSE 0
                END
        END AS position_weight,
        CASE
            WHEN total_events = 1 THEN 1
            WHEN total_events = 2 OR first_event = last_event THEN 0.5
            WHEN touchpoint_at = first_event THEN 0.4
            WHEN touchpoint_at = signup_at THEN 0.4
            WHEN total_events > 2 THEN 0.2 / (total_events - 2)
            ELSE 0
        END AS signup_touch_weight,
        IFF(touchpoint_at = first_event, 1, 0) AS first_touch_weight,
        IFF(touchpoint_at = last_event, 1, 0) AS last_touch_weight
    FROM positioned

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
    campaign_tracking_sk,
    campaign_type,
    ad_format,
    src AS piano_source,
    src_detail AS piano_source_detail,
    src_organic AS organic_source,
    src_organic_detail AS organic_source_detail,
    bbc_team,
    partner,
    is_paid_event = 1 AS is_paid_touch,
    IFF(is_paid_event = 1, 'Paid', attribution_source_unpaid) AS attribution_source,
    IFF(is_paid_event = 1, bbc_team, attribution_source_detail_unpaid) AS attribution_source_detail,
    -- today's promo split adds up to more than 1 when a paid touch is not the first or last, so scale it to 1
    IFF(
        has_promo = 1,
        position_weight / SUM(position_weight) OVER (PARTITION BY conversion_id),
        position_weight
    ) AS position_weight,
    signup_touch_weight,
    first_touch_weight,
    last_touch_weight
FROM weighted
