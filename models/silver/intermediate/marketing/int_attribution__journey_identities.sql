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
The cookies in each buyer's journey: one row per conversion x cookie.

Links are judged on page views inside the journey window: the checkout cookie always; a cookie
carrying the buyer's account; a cookie seen on the buyer's browser (device_first_party_id), unless
that browser had more than var('attribution_max_cookies_per_browser') cookies in the window. A cookie
linked more than one way keeps the first of checkout_cookie, account, device.
*/

{%- set batch_floor = attribution_batch_floor() %}
{%- set lookback_days = var('attribution_lookback_days') %}
{%- set link_types = var('attribution_link_types') %}

WITH conversions AS (

    SELECT
        conversion_id,
        conversion_date,
        conversion_at,
        previous_conversion_at,
        checkout_visitor_id,
        buyer_user_id,
        buyer_device_id
    FROM {{ ref('int_attribution__conversions') }}
    {%- if batch_floor %}
    WHERE conversion_date >= '{{ batch_floor }}'
    {%- endif %}

),

evidence_page_views AS (

    SELECT
        pv.visitor_id,
        IFF(pv.user_id ILIKE 'unidentified%', NULL, NULLIF(pv.user_id, '')) AS user_id,
        pv.device_first_party_id,
        pv.page_view_time
    FROM {{ ref('int_piano__page_views') }} pv
    WHERE
        (
            pv.user_id IN (SELECT c.buyer_user_id FROM conversions c)
            OR pv.device_first_party_id IN (SELECT c.buyer_device_id FROM conversions c)
        )
        {%- if batch_floor %}
        AND pv.page_view_time >= '{{ (batch_floor - modules.datetime.timedelta(days=lookback_days + 1)).isoformat() }}'
        {%- endif %}

),

evidence_in_window AS (

    SELECT
        c.conversion_id,
        c.checkout_visitor_id,
        c.buyer_user_id,
        c.buyer_device_id,
        e.visitor_id,
        e.user_id,
        e.device_first_party_id
    FROM conversions c
    JOIN evidence_page_views e
        ON (e.user_id = c.buyer_user_id OR e.device_first_party_id = c.buyer_device_id)
        AND e.page_view_time <= c.conversion_at
        AND DATEDIFF(DAY, e.page_view_time, c.conversion_at) <= {{ lookback_days }}
        AND (c.previous_conversion_at IS NULL OR e.page_view_time > c.previous_conversion_at)

),

checkout_links AS (

    SELECT
        conversion_id,
        checkout_visitor_id AS visitor_id,
        'checkout_cookie' AS identity_link_type,
        NULL::NUMBER AS browser_cookie_count
    FROM conversions

),

account_links AS (

    SELECT DISTINCT
        conversion_id,
        visitor_id,
        'account' AS identity_link_type,
        NULL::NUMBER AS browser_cookie_count
    FROM evidence_in_window
    WHERE
        user_id = buyer_user_id
        AND visitor_id != checkout_visitor_id

),

browser_sizes AS (

    SELECT
        conversion_id,
        COUNT(DISTINCT visitor_id) AS browser_cookie_count
    FROM evidence_in_window
    WHERE device_first_party_id = buyer_device_id
    GROUP BY conversion_id

),

device_links AS (

    SELECT
        e.conversion_id,
        e.visitor_id,
        'device' AS identity_link_type,
        MAX(b.browser_cookie_count) AS browser_cookie_count
    FROM evidence_in_window e
    JOIN browser_sizes b ON e.conversion_id = b.conversion_id
    WHERE
        e.device_first_party_id = e.buyer_device_id
        AND e.visitor_id != e.checkout_visitor_id
        AND b.browser_cookie_count <= {{ var('attribution_max_cookies_per_browser') }}
    GROUP BY e.conversion_id, e.visitor_id, e.buyer_user_id
    -- a cookie that carries a different real account belongs to someone else
    HAVING COUNT_IF(e.user_id IS NOT NULL AND e.user_id != COALESCE(e.buyer_user_id, '')) = 0

),

all_links AS (

    SELECT
        conversion_id,
        visitor_id,
        identity_link_type,
        browser_cookie_count
    FROM checkout_links
    {%- if 'account' in link_types %}

    UNION ALL

    SELECT
        conversion_id,
        visitor_id,
        identity_link_type,
        browser_cookie_count
    FROM account_links
    {%- endif %}
    {%- if 'device' in link_types %}

    UNION ALL

    SELECT
        conversion_id,
        visitor_id,
        identity_link_type,
        browser_cookie_count
    FROM device_links
    {%- endif %}

)

SELECT
    l.conversion_id,
    l.visitor_id,
    c.conversion_date,
    l.identity_link_type,
    l.browser_cookie_count
FROM all_links l
JOIN conversions c ON l.conversion_id = c.conversion_id
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY l.conversion_id, l.visitor_id
    ORDER BY DECODE(l.identity_link_type, 'checkout_cookie', 1, 'account', 2, 3)
) = 1
