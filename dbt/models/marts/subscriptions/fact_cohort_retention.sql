{{ config(materialized='table') }}

WITH cohort_base AS (

    SELECT
        subscription_id,
        term_id,
        DATE_TRUNC(MONTH, conversion_date) AS cohort_month,
        months_since_conversion
    FROM
        {{ ref('fact_subscriber_daily_snapshot') }}
    WHERE
        subscriber_status = 'Active'
        -- AND term_id = 'TMUO13PYIA2B'

),

cohort_counts AS (

    SELECT
        term_id,
        cohort_month,
        months_since_conversion,
        COUNT(DISTINCT subscription_id) as active_subscribers
    FROM cohort_base
    GROUP BY ALL

),

cohort_sizes AS (

    SELECT
        term_id,
        cohort_month,
        active_subscribers as original_size
    FROM cohort_counts
    WHERE months_since_conversion = 0

)

SELECT

    c.term_id,
    TO_CHAR(c.cohort_month, 'YYYY-MM') AS cohort,
    s.original_size AS cohort_size,
    c.months_since_conversion,
    c.active_subscribers,
    c.active_subscribers / NULLIF(s.original_size, 0) as retention_rate

FROM cohort_counts c
JOIN cohort_sizes s
    ON c.cohort_month = s.cohort_month
    AND c.term_id = s.term_id
ORDER BY 1, 2, 4
