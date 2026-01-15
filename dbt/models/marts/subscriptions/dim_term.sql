{{ config(materialized="table") }}

SELECT DISTINCT
    term_id,
    term_name,
    billing_period,
    term_offer_id,
    term_offer_name
FROM {{ ref('stg_piano__subs_events_web') }}
WHERE
    term_offer_id IS NOT NULL
    AND term_id IS NOT NULL
    AND billing_period IS NOT NULL
