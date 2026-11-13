{{
    config(
        materialized="table",
        tags=['subscriptions', 'piano', 'mart', 'dim']
    )
}}

-- Bridge between offers and the terms they sell: a term can be sold through
-- several offers. Keeps every link the Piano API has listed; links removed
-- since are flagged rather than dropped.
SELECT
    MD5(offer_id || '|' || term_id) AS offer_term_id,
    offer_id,
    term_id,
    MIN(snapshot_date) AS first_listed_date,
    MAX(snapshot_date) AS last_listed_date,
    MAX(snapshot_date) = (
        SELECT MAX(snapshot_date) FROM {{ ref('stg_piano__offers') }}
    ) AS is_listed_in_piano
FROM {{ ref('stg_piano__offer_terms') }}
GROUP BY offer_id, term_id
