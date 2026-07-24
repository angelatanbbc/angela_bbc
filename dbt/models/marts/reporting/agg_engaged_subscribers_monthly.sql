{{ config(
    materialized='table',
    tags=['subscriptions', 'piano', 'mart', 'reporting']
) }}

WITH subscriber_activity AS (

    SELECT
        date_day,
        user_first_party_id,
        is_engaged
    FROM {{ ref('fact_subscriber_activity_daily') }}

),

months AS (

    SELECT DISTINCT
        month_start_date,
        month_end_date
    FROM {{ ref('dim_date') }}
    WHERE month_start_date <= CURRENT_DATE

),

active_subscribers AS (

    SELECT
        m.month_start_date,
        COUNT(DISTINCT sa.user_first_party_id) AS active_subscribers
    FROM months m
    JOIN subscriber_activity sa
        ON sa.date_day BETWEEN m.month_start_date AND m.month_end_date
    GROUP BY m.month_start_date

),

engaged_subscribers AS (

    SELECT
        m.month_start_date,
        COUNT(DISTINCT IFF(sa.is_engaged, sa.user_first_party_id, NULL)) AS engaged_subscribers
    FROM months m
    JOIN subscriber_activity sa
        ON sa.date_day BETWEEN m.month_start_date AND m.month_end_date
    GROUP BY m.month_start_date

)

SELECT
    m.month_start_date,
    COALESCE(a.active_subscribers, 0) AS active_subscribers,
    COALESCE(e.engaged_subscribers, 0) AS engaged_subscribers,
    COALESCE(e.engaged_subscribers, 0) / NULLIF(COALESCE(a.active_subscribers, 0), 0) AS engaged_subscriber_rate
FROM months m
LEFT JOIN active_subscribers a
    ON m.month_start_date = a.month_start_date
LEFT JOIN engaged_subscribers e
    ON m.month_start_date = e.month_start_date
WHERE COALESCE(a.active_subscribers, 0) > 0
   OR COALESCE(e.engaged_subscribers, 0) > 0
ORDER BY m.month_start_date
