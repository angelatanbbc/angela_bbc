{{ config(materialized="table") }}

SELECT
    term_id,
    MAX(term_name) AS term_name,
    MAX(billing_period) AS billing_period,
    MAX(COALESCE(term_offer_id, 'OFR1N7V2XJPI')) AS term_offer_id,
    MAX(COALESCE(term_offer_name, 'BBC Subscription')) AS term_offer_name
FROM {{ ref('fact_conversions') }}
WHERE
    term_id IS NOT NULL
    AND billing_period IS NOT NULL
GROUP BY term_id
