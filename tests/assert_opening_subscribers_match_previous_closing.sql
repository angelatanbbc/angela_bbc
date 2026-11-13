/*
    Opening stock of each month equals the closing stock of the month before, by billing period,
    billing channel and subscription country. These are the day-start columns that
    sv_bbc_com.opening_active_subscribers and opening_mrr read, against the day-end columns that
    active_subscribers and mrr read. Returns one row for each group and month that does not match.
*/

WITH snapshot AS (

    SELECT
        s.date_day,
        DATE_TRUNC(MONTH, s.date_day) AS month_start,
        s.subscription_id,
        s.subscriber_status,
        s.mrr_amount,
        s.is_active_at_day_start,
        s.day_start_mrr_amount,
        COALESCE(t.billing_period, 'N/A') AS billing_period,
        COALESCE(t.billing_channel, 'N/A') AS billing_channel,
        COALESCE(ds.subscription_country, 'N/A') AS subscription_country
    FROM {{ ref('fct_subscriber_daily_snapshot') }} s
    LEFT JOIN {{ ref('dim_term') }} t
        ON s.term_id = t.term_id
    LEFT JOIN {{ ref('dim_subscription') }} ds
        ON s.subscription_id = ds.subscription_id

),

date_range AS (

    SELECT
        MIN(month_start) AS first_month_start,
        MAX(date_day) AS last_date_day
    FROM snapshot

),

opening AS (

    SELECT
        month_start,
        billing_period,
        billing_channel,
        subscription_country,
        COUNT(DISTINCT IFF(is_active_at_day_start, subscription_id, NULL)) AS opening_subscribers,
        SUM(day_start_mrr_amount) AS opening_mrr
    FROM snapshot
    WHERE date_day = month_start
    GROUP BY ALL

),

previous_closing AS (

    SELECT
        DATEADD(MONTH, 1, month_start) AS month_start,
        billing_period,
        billing_channel,
        subscription_country,
        COUNT(DISTINCT IFF(subscriber_status = 'Active', subscription_id, NULL))
            AS previous_closing_subscribers,
        SUM(mrr_amount) AS previous_closing_mrr
    FROM snapshot
    WHERE date_day = LAST_DAY(date_day)
    GROUP BY ALL

),

compared AS (

    SELECT
        COALESCE(o.month_start, c.month_start) AS month_start,
        COALESCE(o.billing_period, c.billing_period) AS billing_period,
        COALESCE(o.billing_channel, c.billing_channel) AS billing_channel,
        COALESCE(o.subscription_country, c.subscription_country) AS subscription_country,
        ZEROIFNULL(o.opening_subscribers) AS opening_subscribers,
        ZEROIFNULL(c.previous_closing_subscribers) AS previous_closing_subscribers,
        ZEROIFNULL(o.opening_mrr) AS opening_mrr,
        ZEROIFNULL(c.previous_closing_mrr) AS previous_closing_mrr
    FROM opening o
    FULL OUTER JOIN previous_closing c
        ON
            o.month_start = c.month_start
            AND o.billing_period = c.billing_period
            AND o.billing_channel = c.billing_channel
            AND o.subscription_country = c.subscription_country

)

SELECT c.*
FROM compared c
CROSS JOIN date_range r
WHERE
    c.month_start > r.first_month_start
    AND c.month_start <= r.last_date_day
    AND (
        c.opening_subscribers != c.previous_closing_subscribers
        OR ABS(c.opening_mrr - c.previous_closing_mrr) > 0.01
    )
