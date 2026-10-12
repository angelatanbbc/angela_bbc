{{ config(
    materialized='table',
    tags=['intermediate']
) }}

-- 1. Get the "birth" event: each subscriber's first-ever subscription
WITH first_event AS (
    SELECT
        e.subscription_id,
        IFF(exp.experience_name ILIKE '%lfv%', 'LFV', 'Non-LFV') AS experience_type,  -- Classify as LFV vs Non-LFV based on experience_name
        e.event_time::DATE AS start_date,
        e.term_id,
        e.billing_period,
        e.conversion_app_type_id,
        e.conversion_device_type_id,
        e.conversion_os_group_id
    FROM
        {{ ref('fct_subscription_events') }} e
    LEFT JOIN (SELECT * FROM {{ ref('fct_conversions') }} QUALIFY ROW_NUMBER() OVER (PARTITION BY conversion_id ORDER BY conversion_time) = 1) c
        ON e.subscription_id = c.subscription_id
    LEFT JOIN {{ ref('dim_experience') }} exp
        ON c.experience_id = exp.experience_id
    WHERE
        e.subscription_action = 'New subscription'

),

-- 2. Get the "death" event: the churn date, if it exists
churn_event AS (
    SELECT
        subscription_id,
        event_time::DATE AS churn_date
    FROM
        {{ ref('fct_subscription_events') }}
    WHERE
        subscription_action IN ('Canceled', 'Expired', 'Renewal failed, will not retry') -- Define churn event types
),

-- 3. Combine them to build the final survival table
final_survival_table AS (
    SELECT
        f.subscription_id,
        f.experience_type,
        f.term_id,
        f.billing_period,
        f.conversion_app_type_id,
        f.conversion_device_type_id,
        f.conversion_os_group_id,
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
    experience_type,
    term_id,
    billing_period,
    conversion_app_type_id,
    conversion_device_type_id,
    conversion_os_group_id,
    start_date,
    churn_date,
    
    -- The event is a 1 (churn) if a churn date exists AND it's before today
    CASE 
        WHEN churn_date IS NOT NULL AND churn_date <= censoring_date THEN 1
        ELSE 0 -- Otherwise, the subscriber is "censored" (still active)
    END AS churn_event,
    
    -- Calculate the total observed duration in days
    DATEDIFF(
        'day',
        start_date,
        -- Use the earlier of the two possible end dates
        LEAST(COALESCE(churn_date, censoring_date), censoring_date)
    ) AS duration_days
    
FROM
    final_survival_table
