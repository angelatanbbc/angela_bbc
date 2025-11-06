{{ config(materialized="table") }}

WITH date_spine AS (
    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="cast('2025-06-25' as date)",
        end_date="cast('2030-12-31' as date)"
    )
    }}
),

date_dimension AS (
    SELECT
        -- Primary Key
        date_day AS date_key,

        -- Date identifiers
        date_day,
        CAST(TO_CHAR(date_day, 'YYYYMMDD') AS INTEGER) AS date_id,

        -- Day attributes
        EXTRACT(DAY FROM date_day) AS day_of_month,
        EXTRACT(DOY FROM date_day) AS day_of_year,
        EXTRACT(DOW FROM date_day) AS day_of_week,
        TO_CHAR(date_day, 'Day') AS day_name,
        TO_CHAR(date_day, 'Dy') AS day_name_short,
        DATEADD('second', -1, DATEADD('day', 1, DATE_TRUNC('day', date_day))) AS day_end_timestamp,

        -- Week attributes
        EXTRACT(WEEK FROM date_day) AS week_of_year,
        DATE_TRUNC('week', date_day) AS week_start_date,
        DATEADD(DAY, 6, DATE_TRUNC('week', date_day)) AS week_end_date,

        -- Month attributes
        EXTRACT(MONTH FROM date_day) AS month_of_year,
        TO_CHAR(date_day, 'Month') AS month_name,
        TO_CHAR(date_day, 'Mon') AS month_name_short,
        DATE_TRUNC('month', date_day) AS month_start_date,
        LAST_DAY(date_day) AS month_end_date,

        -- Quarter attributes
        EXTRACT(QUARTER FROM date_day) AS quarter_of_year,
        'Q' || EXTRACT(QUARTER FROM date_day) AS quarter_name,
        DATE_TRUNC('quarter', date_day) AS quarter_start_date,
        LAST_DAY(DATE_TRUNC('quarter', date_day) + INTERVAL '2 months') AS quarter_end_date,

        -- Year attributes
        EXTRACT(YEAR FROM date_day) AS year,
        DATE_TRUNC('year', date_day) AS year_start_date,
        DATEADD(DAY, -1, DATEADD(YEAR, 1, DATE_TRUNC('year', date_day))) AS year_end_date,

        -- Year-Month combination
        TO_CHAR(date_day, 'YYYY-MM') AS year_month,

        -- Fiscal attributes (assuming fiscal year starts in April)
        CASE
            WHEN EXTRACT(MONTH FROM date_day) >= 4
            THEN EXTRACT(YEAR FROM date_day)
            ELSE EXTRACT(YEAR FROM date_day) - 1
        END AS fiscal_year,

        CASE
            WHEN EXTRACT(MONTH FROM date_day) BETWEEN 4 AND 6 THEN 1
            WHEN EXTRACT(MONTH FROM date_day) BETWEEN 7 AND 9 THEN 2
            WHEN EXTRACT(MONTH FROM date_day) BETWEEN 10 AND 12 THEN 3
            ELSE 4
        END AS fiscal_quarter,

        -- Boolean flags
        CASE WHEN EXTRACT(DOW FROM date_day) IN (0, 6) THEN TRUE ELSE FALSE END AS is_weekend,
        CASE WHEN EXTRACT(DOW FROM date_day) BETWEEN 1 AND 5 THEN TRUE ELSE FALSE END AS is_weekday,
        CASE WHEN EXTRACT(DAY FROM date_day) = 1 THEN TRUE ELSE FALSE END AS is_first_day_of_month,
        CASE WHEN date_day = LAST_DAY(date_day) THEN TRUE ELSE FALSE END AS is_last_day_of_month,
        CASE WHEN date_day = DATE_TRUNC('quarter', date_day) THEN TRUE ELSE FALSE END AS is_first_day_of_quarter,
        CASE WHEN date_day = LAST_DAY(DATE_TRUNC('quarter', date_day) + INTERVAL '2 months') THEN TRUE ELSE FALSE END AS is_last_day_of_quarter,

        -- Relative date helpers
        CASE WHEN date_day = CURRENT_DATE THEN TRUE ELSE FALSE END AS is_today,
        CASE WHEN date_day = CURRENT_DATE - 1 THEN TRUE ELSE FALSE END AS is_yesterday,
        CASE WHEN date_day BETWEEN DATE_TRUNC('week', CURRENT_DATE) AND CURRENT_DATE THEN TRUE ELSE FALSE END AS is_current_week,
        CASE WHEN date_day BETWEEN DATE_TRUNC('month', CURRENT_DATE) AND CURRENT_DATE THEN TRUE ELSE FALSE END AS is_current_month,
        CASE WHEN date_day BETWEEN DATE_TRUNC('quarter', CURRENT_DATE) AND CURRENT_DATE THEN TRUE ELSE FALSE END AS is_current_quarter,
        CASE WHEN date_day BETWEEN DATE_TRUNC('year', CURRENT_DATE) AND CURRENT_DATE THEN TRUE ELSE FALSE END AS is_current_year,

        -- Days from today
        DATEDIFF(DAY, date_day, CURRENT_DATE) AS days_from_today

    FROM date_spine
)

SELECT *
FROM date_dimension
ORDER BY date_key
