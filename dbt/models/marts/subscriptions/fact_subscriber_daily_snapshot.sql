{{ config(materialized="table") }}


-- 1. Get all subscription events (the transaction log)
WITH subscription_events AS (
    
    SELECT
        subscription_id,
        event_date,
        event_time,
        event_type,
        term_id,
        billing_period,
        mrr_change_amount,
        subscription_period_number,
        geo_country,
        geo_region
    FROM
        {{ ref('fact_subscription_events') }}

),

-- 2. Get date dimension for the date range of subscription events
dim_date AS (

    SELECT
        date_day,
        day_end_timestamp
    FROM
        {{ ref('dim_date') }}
    WHERE
        date_day BETWEEN (SELECT MIN(event_date) FROM subscription_events)
                     AND (SELECT MAX(event_date) FROM subscription_events)

),

-- 3. Calculate the state of each subscriber *at the time of each event*
-- This creates "state change" rows with a running MRR total
subscriber_states AS (

    SELECT
        subscription_id,
        event_date,
        event_type,
        term_id,
        billing_period,
        geo_country,
        geo_region,
        subscription_period_number,
        event_time AS valid_from_time,

        -- The time until the next event for this subscription
        LEAD(event_time) OVER (
            PARTITION BY subscription_id
            ORDER BY event_time
        ) AS valid_to_time,

        -- Running total of MRR changes to get current MRR
        SUM(mrr_change_amount) OVER (
            PARTITION BY subscription_id
            ORDER BY event_time
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS mrr_amount

    FROM subscription_events

),

-- 4. Final snapshot of subscriber daily states
final_snapshot AS (

    SELECT
        d.date_day AS date,
        s.subscription_id,

        -- State attributes
        COALESCE(ss.event_type, 'No Activity') AS last_subscription_action,
        COALESCE(ss.term_id, 'N/A') AS term_id,
        COALESCE(ss.billing_period, 'N/A') AS billing_period,
        COALESCE(ss.subscription_period_number, 0) AS subscription_period_number,
        COALESCE(ss.geo_country, 'N/A') AS geo_country,
        COALESCE(ss.geo_region, 'N/A') AS geo_region,

        -- State measures
        COALESCE(ss.mrr_amount, 0) AS mrr_amount,

        -- Derived attributes
        CASE
            WHEN COALESCE(ss.mrr_amount, 0) > 0 THEN 'Active'
            WHEN ss.valid_from_time IS NOT NULL THEN 'Churned' -- Was a subscriber, but MRR is 0
            ELSE 'Not Subscribed' -- Never had an event before this date
        END AS subscriber_status

    FROM dim_date d

    CROSS JOIN (SELECT DISTINCT subscription_id FROM subscription_events) s
    
    LEFT JOIN subscriber_states ss
        ON s.subscription_id = ss.subscription_id
        AND d.day_end_timestamp >= ss.valid_from_time
        AND (d.day_end_timestamp < ss.valid_to_time OR ss.valid_to_time IS NULL)

)

SELECT *
FROM final_snapshot