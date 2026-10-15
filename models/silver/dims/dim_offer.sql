{{
    config(
        materialized="table",
        tags=['subscriptions', 'piano', 'mart', 'dim']
    )
}}

WITH offers AS (

    -- Latest snapshot of every offer the Piano API has listed.
    SELECT
        offer_id,
        offer_name,
        offer_status,
        is_deleted,
        created_at,
        updated_at,
        snapshot_date,
        snapshot_date = MAX(snapshot_date) OVER () AS is_listed_in_piano
    FROM {{ ref('stg_piano__offers') }}
    QUALIFY ROW_NUMBER() OVER (PARTITION BY offer_id ORDER BY snapshot_at DESC) = 1

),

offer_term_counts AS (

    SELECT
        offer_id,
        snapshot_date,
        COUNT(*) AS term_count
    FROM {{ ref('stg_piano__offer_terms') }}
    GROUP BY offer_id, snapshot_date

)

SELECT
    o.offer_id,
    o.offer_name,
    o.offer_status,
    COALESCE(c.term_count, 0) AS term_count,
    o.is_deleted,
    o.is_listed_in_piano,
    o.created_at,
    o.updated_at
FROM offers o
LEFT JOIN offer_term_counts c
    ON
        o.offer_id = c.offer_id
        AND o.snapshot_date = c.snapshot_date
