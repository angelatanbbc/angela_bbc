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

weeks AS (

    SELECT DISTINCT
        week_start_date,
        week_end_date
    FROM {{ ref('dim_date') }}
    WHERE week_start_date <= CURRENT_DATE

),

active_subscribers AS (

    SELECT
        w.week_start_date,
        COUNT(DISTINCT sa.user_first_party_id) AS active_subscribers
    FROM weeks w
    JOIN subscriber_activity sa
        ON sa.date_day BETWEEN w.week_start_date AND w.week_end_date
    GROUP BY w.week_start_date

),

engaged_subscribers AS (

    SELECT
        w.week_start_date,
        COUNT(DISTINCT IFF(sa.is_engaged, sa.user_first_party_id, NULL)) AS engaged_subscribers
    FROM weeks w
    JOIN subscriber_activity sa
        ON sa.date_day BETWEEN w.week_start_date AND w.week_end_date
    GROUP BY w.week_start_date

)

SELECT
    w.week_start_date,
    COALESCE(a.active_subscribers, 0) AS active_subscribers,
    COALESCE(e.engaged_subscribers, 0) AS engaged_subscribers,
    COALESCE(e.engaged_subscribers, 0) / NULLIF(COALESCE(a.active_subscribers, 0), 0) AS engaged_subscriber_rate
FROM weeks w
LEFT JOIN active_subscribers a
    ON w.week_start_date = a.week_start_date
LEFT JOIN engaged_subscribers e
    ON w.week_start_date = e.week_start_date
WHERE COALESCE(a.active_subscribers, 0) > 0
   OR COALESCE(e.engaged_subscribers, 0) > 0
ORDER BY w.week_start_date
