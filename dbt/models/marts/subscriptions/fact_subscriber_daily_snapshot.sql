{{ config(materialized="table") }}


-- 1. Get all subscription events (the transaction log)
WITH subscription_events AS (
    
    SELECT *
    FROM {{ ref('fact_subscription_events') }}

),

-- 2. Get date dimension for the date range of subscription events
dim_date AS (

    SELECT
        date_day,
        day_end_timestamp
    FROM
        {{ ref('dim_date') }}
    WHERE
        date_day BETWEEN (SELECT MIN(event_time::DATE) FROM subscription_events)
                     AND (SELECT MAX(event_time::DATE) FROM subscription_events)

),

-- 3. Calculate the state of each subscriber *at the time of each event*
-- This creates "state change" rows with a running MRR total
subscriber_states AS (

    SELECT
        user_id,
        subscription_id,
        event_time::DATE AS event_date,
        event_type,
        term_id,
        term_name,
        billing_period,
        geo_id,
        geo_country,
        geo_region,
        geo_city,
        cohort_month,
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
        d.date_day,
        ss.user_id,
        s.subscription_id,

        -- State attributes
        ss.event_type AS last_subscription_action,
        COALESCE(ss.term_id, 'N/A') AS term_id,
        COALESCE(ss.term_name, 'N/A') AS term_name,
        COALESCE(ss.billing_period, 'N/A') AS billing_period,
        COALESCE(ss.subscription_period_number, 0) AS subscription_period_number,
        COALESCE(ss.geo_id, 'N/A') AS geo_id,
        COALESCE(ss.geo_country, 'N/A') AS geo_country,
        COALESCE(ss.geo_region, 'N/A') AS geo_region,
        COALESCE(ss.geo_city, 'N/A') AS geo_city,
        COALESCE(ss.cohort_month, '1900-01-01'::TIMESTAMP) AS cohort_month,

        -- State measures
        COALESCE(ss.mrr_amount, 0) AS mrr_amount,

        -- Derived attributes
        CASE
            WHEN COALESCE(ss.mrr_amount, 0) > 0 THEN 'Active'
            WHEN ss.valid_from_time IS NOT NULL THEN 'Churned' -- Was a subscriber, but MRR is 0
            ELSE 'Not Subscribed' -- Never had an event before this date
        END AS subscriber_status,

        ZEROIFNULL(
            CASE
                WHEN COALESCE(ss.mrr_amount, 0) = 0 AND ss.valid_from_time IS NOT NULL
                THEN DATEDIFF(DAY, ss.valid_from_time::DATE, d.date_day)
                ELSE NULL
            END
         ) AS days_since_churned

    FROM dim_date d

    CROSS JOIN (SELECT DISTINCT subscription_id FROM subscription_events) s
    
    LEFT JOIN subscriber_states ss
        ON s.subscription_id = ss.subscription_id
        AND d.day_end_timestamp >= ss.valid_from_time
        AND (d.day_end_timestamp < ss.valid_to_time OR ss.valid_to_time IS NULL)

),

lifetime_metrics AS (

    SELECT
        fs.*,
        c.conversion_date,

        -- Days/Months since conversion
        DATEDIFF(DAY, c.conversion_date, fs.date_day) AS days_since_conversion,
        -- Calculate months relative to signup date, not calendar months
        -- Handles month-end edge cases (e.g., signup on Jan 31, anniversary on Feb 28)
        DATEDIFF(MONTH, c.conversion_date, fs.date_day)
            - CASE
                WHEN DAY(fs.date_day) < DAY(c.conversion_date)
                    AND DAY(fs.date_day) < DAY(LAST_DAY(fs.date_day)) THEN 1
                ELSE 0
            END AS months_since_conversion

    FROM final_snapshot fs

    LEFT JOIN (
        SELECT
            subscription_id,
            MIN(event_time::DATE) AS conversion_date
        FROM subscription_events
        WHERE event_type = 'New Subscription'
        GROUP BY subscription_id
    ) c
    ON fs.subscription_id = c.subscription_id

)

SELECT *
FROM lifetime_metrics
WHERE
    last_subscription_action IS NOT NULL
    AND days_since_churned = 0
ORDER BY subscription_id, date_day