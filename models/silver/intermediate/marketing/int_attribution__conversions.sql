{{
    config(
        materialized="table",
        tags=["attribution", "intermediate"]
    )
}}

/*
Attributable web subscription purchases: one row per conversion_id.

checkout_visitor_id is the cookie on the checkout page view, else the purchase event's own;
Piano often writes a fresh cookie on the purchase event. The 'unidentified-user' placeholder
is never treated as the buyer's account.
*/

{%- set touch_columns = attribution_touch_columns() %}

WITH purchase_events AS (

    SELECT
        conversion_id,
        subscription_id,
        pageview_id,
        visitor_id,
        IFF(user_id ILIKE 'unidentified%', NULL, NULLIF(user_id, '')) AS user_id,
        device_first_party_id,
        event_time,
        billing_period,
        vx_promo_code,
        {%- for column in touch_columns %}
        {{ column }},
        {%- endfor %}
        app_type
    FROM {{ ref('int_piano__events_cleaned') }}
    WHERE
        event_name = 'vx.conversion'
        AND conversion_id IS NOT NULL
        AND pageview_id IS NOT NULL
    QUALIFY ROW_NUMBER() OVER (PARTITION BY conversion_id ORDER BY event_time) = 1

),

attributable_purchases AS (

    SELECT
        p.conversion_id,
        p.subscription_id,
        p.pageview_id,
        p.visitor_id,
        p.user_id,
        p.device_first_party_id,
        p.event_time,
        p.billing_period,
        p.vx_promo_code,
        {%- for column in touch_columns %}
        p.{{ column }},
        {%- endfor %}
        s.site_id IS NOT NULL AS is_subscription_site
    FROM purchase_events p
    LEFT JOIN {{ ref('subscription_sites') }} s ON p.site_id = s.site_id
    WHERE
        (p.app_type != 'mobile-app' OR p.app_type IS NULL)
        AND (
            p.vx_promo_code IS NULL
            OR (
                p.vx_promo_code != ''
                AND p.vx_promo_code NOT IN (SELECT e.promo_code FROM {{ ref('excluded_promo_codes') }} e)
            )
        )

),

checkout_page_views AS (

    SELECT
        pv.pageview_id,
        pv.visitor_id,
        IFF(pv.user_id ILIKE 'unidentified%', NULL, NULLIF(pv.user_id, '')) AS user_id,
        pv.device_first_party_id
    FROM {{ ref('int_piano__page_views') }} pv
    WHERE pv.pageview_id IN (SELECT a.pageview_id FROM attributable_purchases a)

),

buyers AS (

    SELECT
        a.conversion_id,
        a.subscription_id,
        a.pageview_id AS checkout_pageview_id,
        COALESCE(c.visitor_id, a.visitor_id) AS checkout_visitor_id,
        a.visitor_id AS conversion_visitor_id,
        COALESCE(a.user_id, c.user_id) AS buyer_user_id,
        COALESCE(a.device_first_party_id, c.device_first_party_id) AS buyer_device_id,
        a.event_time AS conversion_at,
        a.event_time::DATE AS conversion_date,
        -- across all sites, so a purchase on another site still bounds the journey
        LAG(a.event_time) OVER (
            PARTITION BY COALESCE(c.visitor_id, a.visitor_id)
            ORDER BY a.event_time
        ) AS previous_conversion_at,
        a.billing_period,
        a.vx_promo_code AS promo_code,
        a.is_subscription_site,
        {%- for column in touch_columns %}
        a.{{ column }}{{ ',' if not loop.last }}
        {%- endfor %}
    FROM attributable_purchases a
    LEFT JOIN checkout_page_views c ON a.pageview_id = c.pageview_id

)

SELECT
    conversion_id,
    subscription_id,
    checkout_pageview_id,
    checkout_visitor_id,
    conversion_visitor_id,
    buyer_user_id,
    buyer_device_id,
    conversion_at,
    conversion_date,
    previous_conversion_at,
    -- the journey is complete once the page view history reaches the full lookback before it
    conversion_date >= (
        SELECT DATEADD(DAY, {{ var('attribution_lookback_days') }}, MIN(page_view_time)::DATE)
        FROM {{ ref('int_piano__page_views') }}
    ) AS is_lookback_complete,
    billing_period,
    promo_code,
    {%- for column in touch_columns %}
    {{ column }}{{ ',' if not loop.last }}
    {%- endfor %}
FROM buyers
{%- if var('attribution_site_scope') %}
WHERE is_subscription_site
{%- endif %}
