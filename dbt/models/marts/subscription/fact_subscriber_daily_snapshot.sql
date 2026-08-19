{{
    config(
        materialized="table",
        tags=['fct', 'subscriptions']
    )
}}

WITH subscription_events AS (

    SELECT *
    FROM {{ ref('fact_subscription_events') }}

),

dim_subscription AS (

    SELECT
        subscription_id,
        user_first_party_id,
        term_id,
        term_name,
        billing_period,
        subscription_period_number
    FROM {{ ref('dim_subscription') }}

),

date_spine AS (

    SELECT
        date_day,
        day_end_timestamp
    FROM {{ ref('dim_date') }}
    WHERE
        date_day BETWEEN (SELECT MIN(event_time::DATE) FROM subscription_events)
                     AND (SELECT MAX(event_time::DATE) FROM subscription_events)

),

subscription_state_periods AS (

    SELECT
        subscription_id,
        conversion_app_type_id,
        conversion_device_type_id,
        conversion_os_group_id,
        subscription_action AS last_subscription_action,
        term_id AS event_term_id,
        term_name AS event_term_name,
        billing_period AS event_billing_period,
        subscription_period_number AS event_subscription_period_number,
        geo_id,
        geo_country,
        geo_region,
        geo_city,
        cohort_month,
        event_time AS valid_from_time,
        LEAD(event_time) OVER (
            PARTITION BY subscription_id
            ORDER BY event_time
        ) AS valid_to_time,
        SUM(mrr_change_amount) OVER (
            PARTITION BY subscription_id
            ORDER BY event_time
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS mrr_amount
    FROM subscription_events

),

subscription_days AS (

    SELECT
        d.date_day,
        s.subscription_id,
        NULL as user_id,
        ds.user_first_party_id,
        sp.conversion_app_type_id,
        sp.conversion_device_type_id,
        sp.conversion_os_group_id,
        sp.last_subscription_action,
        COALESCE(ds.term_id, 'N/A') AS term_id,
        COALESCE(ds.term_name, 'N/A') AS term_name,
        COALESCE(ds.billing_period, 'N/A') AS billing_period,
        COALESCE(sp.event_subscription_period_number, 1) AS subscription_period_number,
        {{ generate_geo_id('sp.geo_country', 'sp.geo_region') }} AS geo_id,
        COALESCE(sp.geo_country, 'Unknown') AS geo_country,
        COALESCE(sp.geo_region, 'Unknown') AS geo_region,
        COALESCE(sp.geo_city, 'Unknown') AS geo_city,
        COALESCE(sp.cohort_month, '1900-01') AS cohort_month,
        COALESCE(sp.mrr_amount, 0) AS mrr_amount,
        sp.valid_from_time,
        CASE
            WHEN COALESCE(sp.mrr_amount, 0) > 0 THEN 'Active'
            WHEN sp.valid_from_time IS NOT NULL THEN 'Churned'
            ELSE 'Not Subscribed'
        END AS subscriber_status
    FROM date_spine d
    CROSS JOIN (SELECT DISTINCT subscription_id FROM subscription_events) s
    LEFT JOIN subscription_state_periods sp
        ON s.subscription_id = sp.subscription_id
        AND d.day_end_timestamp >= sp.valid_from_time
        AND (d.day_end_timestamp < sp.valid_to_time OR sp.valid_to_time IS NULL)
    LEFT JOIN dim_subscription ds
        ON s.subscription_id = ds.subscription_id

),

conversion_dates AS (

    SELECT
        subscription_id,
        MIN(event_time::DATE) AS conversion_date
    FROM subscription_events
    WHERE subscription_action = 'New subscription'
    GROUP BY subscription_id

),

final AS (

    SELECT
        sd.date_day,
        sd.user_id,
        sd.user_first_party_id,
        sd.subscription_id,
        sd.conversion_app_type_id,
        sd.conversion_device_type_id,
        sd.conversion_os_group_id,
        sd.last_subscription_action,
        sd.term_id,
        sd.term_name,
        sd.billing_period,
        sd.subscription_period_number,
        sd.geo_id,
        sd.geo_country,
        sd.geo_region,
        sd.geo_city,
        sd.cohort_month,
        sd.mrr_amount,
        sd.subscriber_status,
        ZEROIFNULL(
            CASE
                WHEN sd.mrr_amount = 0 AND sd.valid_from_time IS NOT NULL
                THEN DATEDIFF(DAY, sd.valid_from_time::DATE, sd.date_day)
                ELSE NULL
            END
        ) AS days_since_churned,
        cd.conversion_date,
        DATEDIFF(DAY, cd.conversion_date, sd.date_day) AS days_since_conversion,
        DATEDIFF(MONTH, cd.conversion_date, sd.date_day)
            - CASE
                WHEN DAY(sd.date_day) < DAY(cd.conversion_date)
                    AND DAY(sd.date_day) < DAY(LAST_DAY(sd.date_day)) THEN 1
                ELSE 0
            END AS months_since_conversion
    FROM subscription_days sd
    LEFT JOIN conversion_dates cd
        ON sd.subscription_id = cd.subscription_id

)

SELECT *
FROM final
WHERE
    last_subscription_action IS NOT NULL
    AND days_since_churned = 0
ORDER BY subscription_id, date_day
