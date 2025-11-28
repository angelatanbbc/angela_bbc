-- models/analysis/survival_data.sql

-- 1. Get the "birth" event: each subscriber's first-ever subscription
WITH first_event AS (
    SELECT
        subscription_id,
        event_date AS start_date,
        billing_period

    FROM
        {{ ref('fact_subscription_events') }}
    WHERE
        event_type = 'New Subscription' -- Or any "birth" event type
),

-- 2. Get the "death" event: the churn date, if it exists
churn_event AS (
    SELECT
        subscription_id,
        event_date AS churn_date
    FROM
        {{ ref('fact_subscription_events') }}
    WHERE
        event_type IN ('Canceled', 'Expired', 'Renewal failed, will not retry') -- Define churn event types
),

-- 3. Combine them to build the final survival table
final_survival_table AS (
    SELECT
        f.subscription_id,
        f.billing_period,
        f.start_date,
        c.churn_date,
        
        -- Today is the "censoring" date for all active subscribers
        CURRENT_DATE() AS censoring_date
        
    FROM
        first_event f
    LEFT JOIN
        churn_event c ON f.subscription_id = c.subscription_id
)

-- 4. Calculate the final duration and event status
SELECT
    subscription_id,
    billing_period,
    
    -- The event is a 1 (churn) if a churn date exists AND it's before today
    CASE 
        WHEN churn_date IS NOT NULL AND churn_date <= censoring_date THEN 1
        ELSE 0 -- Otherwise, the subscriber is "censored" (still active)
    END AS event_status,
    
    -- Calculate the total observed duration in days
    DATEDIFF(
        'day',
        start_date,
        -- Use the earlier of the two possible end dates
        LEAST(COALESCE(churn_date, censoring_date), censoring_date)
    ) AS duration_days
    
FROM
    final_survival_table