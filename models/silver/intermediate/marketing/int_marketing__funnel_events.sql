{{
    config(
        materialized="incremental",
        incremental_strategy="merge",
        unique_key="event_id",
        on_schema_change="fail",
        tags=["marketing", "intermediate"]
    )
}}

/*
The events the paid visitor funnel follows: one row per event that is a paywall or inline-offer
exposure, a click on either, an attributable purchase (int_attribution__conversions, so "converted"
counts the same purchases as the attribution), or a newsletter sign-up. Events of any visitor, paid
or not: fct_paid_visitor_funnel links them to paid visitors.

Newsletter sign-ups: those on a page view, plus those on the newsletters page of
var('marketing_site_ids'), which never carries a pageview_id; the latter have no browser id link.
Incremental: rereads the Piano events from the day before the latest one loaded.
*/

{%- set floor = incremental_date_floor('event_time') %}

WITH conversions AS (

    SELECT conversion_id
    FROM {{ ref('int_attribution__conversions') }}

),

cleaned AS (

    SELECT
        event_id,
        event_name,
        event_time,
        pageview_id,
        visit_id,
        visitor_id,
        user_id,
        IFF(pageview_id IS NULL, NULL, device_first_party_id) AS device_first_party_id,
        conversion_id,
        template_display_mode,
        template_closable,
        term_offer_name
    FROM {{ ref('int_piano__events_cleaned') }}
    WHERE
        event_name IN ('experience.action', 'experience.interaction', 'vx.conversion', 'newsletter.subscribe')
        AND event_time >= '{{ floor if floor else var("marketing_start_date") }}'
        AND (
            pageview_id IS NOT NULL
            OR (
                event_name = 'newsletter.subscribe'
                AND page = 'newsletters.page'
                AND site_id IN ({{ var('marketing_site_ids') | join(', ') }})
            )
        )

),

classified AS (

    SELECT
        event_id,
        event_time,
        pageview_id,
        visit_id,
        visitor_id,
        user_id,
        device_first_party_id,
        IFF(event_name = 'experience.action' AND {{ is_paywall_template() }}, 1, 0) AS is_paywall,
        IFF(event_name = 'experience.interaction' AND {{ is_paywall_template() }}, 1, 0) AS is_paywall_interaction,
        IFF(event_name = 'experience.action' AND {{ is_offer_template() }}, 1, 0) AS is_offer,
        IFF(event_name = 'experience.interaction' AND {{ is_offer_template() }}, 1, 0) AS is_offer_interaction,
        IFF(event_name = 'vx.conversion' AND conversion_id IN (SELECT c.conversion_id FROM conversions c), 1, 0)
            AS is_conversion,
        IFF(
            event_name = 'vx.conversion'
            AND conversion_id IN (SELECT c.conversion_id FROM conversions c)
            AND {{ is_paywall_template() }},
            1,
            0
        ) AS is_paywall_conversion,
        IFF(event_name = 'newsletter.subscribe', 1, 0) AS is_newsletter
    FROM cleaned

)

SELECT
    event_id,
    pageview_id,
    visit_id,
    visitor_id,
    IFF(user_id ILIKE 'unidentified%', NULL, NULLIF(user_id, '')) AS user_id,
    device_first_party_id,
    event_time,
    is_paywall,
    is_paywall_interaction,
    is_offer,
    is_offer_interaction,
    is_conversion,
    is_paywall_conversion,
    is_newsletter
FROM classified
WHERE is_paywall + is_paywall_interaction + is_offer + is_offer_interaction + is_conversion + is_newsletter > 0
QUALIFY ROW_NUMBER() OVER (PARTITION BY event_id ORDER BY pageview_id NULLS LAST) = 1
