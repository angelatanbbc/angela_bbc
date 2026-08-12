{{
    config(
        materialized='table',
        tags=['fct', 'subscriptions']
    )
}}

WITH cohort_base AS (

    SELECT DISTINCT
        subscription_id,
        term_id,
        conversion_app_type_id,
        conversion_device_type_id,
        conversion_os_group_id,
        billing_plan,
        DATE_TRUNC(MONTH, conversion_date) AS cohort_month,
        months_since_conversion
    FROM
        {{ ref('fact_subscriber_daily_snapshot') }}
    WHERE
        subscriber_status = 'Active'
    ORDER BY cohort_month, subscription_id, months_since_conversion

),

cohort_counts AS (

    SELECT
        term_id,
        conversion_app_type_id,
        conversion_device_type_id,
        conversion_os_group_id,
        billing_plan,
        cohort_month,
        months_since_conversion,
        COUNT(DISTINCT subscription_id) AS active_subscribers
    FROM cohort_base
    WHERE DATEADD(MONTH, months_since_conversion, cohort_month) < DATE_TRUNC(MONTH, CURRENT_DATE())
    GROUP BY ALL

),

cohort_sizes AS (

    SELECT
        term_id,
        conversion_app_type_id,
        conversion_device_type_id,
        conversion_os_group_id,
        billing_plan,
        cohort_month,
        active_subscribers as original_size
    FROM cohort_counts
    WHERE months_since_conversion = 0

)

SELECT
    term_id,
    conversion_app_type_id,
    conversion_device_type_id,
    conversion_os_group_id,
    billing_plan,
    TO_CHAR(cohort_month, 'YYYY-MM') AS cohort,
    s.original_size AS cohort_size,
    c.months_since_conversion,
    c.active_subscribers
FROM cohort_counts c
JOIN cohort_sizes s
    USING (term_id, conversion_app_type_id, conversion_device_type_id, conversion_os_group_id, billing_plan, cohort_month)
ORDER BY 1 ASC, 2 ASC, 3 ASC, 4 ASC, 5 DESC
