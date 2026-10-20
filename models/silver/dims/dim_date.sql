{{
    config(
        materialized="table",
        tags=["mart","core",'dim']
    )
}}

WITH date_spine AS (
    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="cast('2025-06-25' as date)",
        end_date="cast('2030-12-31' as date)"
    )
    }}
),

-- UK financial year runs 1 April to 31 March, labelled by its starting calendar year
date_base AS (
    SELECT
        date_day,
        CASE
            WHEN EXTRACT(MONTH FROM date_day) >= 4
            THEN EXTRACT(YEAR FROM date_day)
            ELSE EXTRACT(YEAR FROM date_day) - 1
        END AS fiscal_year,
        CASE
            WHEN EXTRACT(MONTH FROM CURRENT_DATE) >= 4
            THEN EXTRACT(YEAR FROM CURRENT_DATE)
            ELSE EXTRACT(YEAR FROM CURRENT_DATE) - 1
        END AS current_fiscal_year
    FROM date_spine
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
        -- Snowflake's TO_CHAR has no full day-name format ('Day' renders as day number, 'a' and year)
        DECODE(
            DAYNAME(date_day),
            'Mon', 'Monday',
            'Tue', 'Tuesday',
            'Wed', 'Wednesday',
            'Thu', 'Thursday',
            'Fri', 'Friday',
            'Sat', 'Saturday',
            'Sun', 'Sunday'
        ) AS day_name,
        TO_CHAR(date_day, 'Dy') AS day_name_short,
        DATEADD('second', -1, DATEADD('day', 1, DATE_TRUNC('day', date_day))) AS day_end_timestamp,

        -- Week attributes
        EXTRACT(WEEK FROM date_day) AS week_of_year,
        DATE_TRUNC('week', date_day) AS week_start_date,
        DATEADD(DAY, 6, DATE_TRUNC('week', date_day)) AS week_end_date,

        -- Month attributes
        EXTRACT(MONTH FROM date_day) AS month_of_year,
        TO_CHAR(date_day, 'MMMM') AS month_name,
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

        -- Fiscal attributes (UK financial year, 1 April to 31 March)
        fiscal_year,
        TO_CHAR(fiscal_year) || '/' || RIGHT(TO_CHAR(fiscal_year + 1), 2) AS fiscal_year_label,

        CASE
            WHEN EXTRACT(MONTH FROM date_day) BETWEEN 4 AND 6 THEN 1
            WHEN EXTRACT(MONTH FROM date_day) BETWEEN 7 AND 9 THEN 2
            WHEN EXTRACT(MONTH FROM date_day) BETWEEN 10 AND 12 THEN 3
            ELSE 4
        END AS fiscal_quarter,

        -- Boolean flags
        COALESCE(EXTRACT(DOW FROM date_day) IN (0, 6), FALSE) AS is_weekend,
        COALESCE(EXTRACT(DOW FROM date_day) BETWEEN 1 AND 5, FALSE) AS is_weekday,
        COALESCE(EXTRACT(DAY FROM date_day) = 1, FALSE) AS is_first_day_of_month,
        COALESCE(date_day = LAST_DAY(date_day), FALSE) AS is_last_day_of_month,
        COALESCE(date_day = DATE_TRUNC('quarter', date_day), FALSE) AS is_first_day_of_quarter,
        COALESCE(date_day = LAST_DAY(DATE_TRUNC('quarter', date_day) + INTERVAL '2 months'), FALSE) AS is_last_day_of_quarter,

        -- Relative date helpers
        COALESCE(date_day = CURRENT_DATE, FALSE) AS is_today,
        COALESCE(date_day = CURRENT_DATE - 1, FALSE) AS is_yesterday,
        COALESCE(date_day BETWEEN DATE_TRUNC('week', CURRENT_DATE) AND CURRENT_DATE, FALSE) AS is_current_week,
        COALESCE(date_day BETWEEN DATE_TRUNC('month', CURRENT_DATE) AND CURRENT_DATE, FALSE) AS is_current_month,
        COALESCE(date_day BETWEEN DATE_TRUNC('quarter', CURRENT_DATE) AND CURRENT_DATE, FALSE) AS is_current_quarter,
        COALESCE(date_day BETWEEN DATE_TRUNC('year', CURRENT_DATE) AND CURRENT_DATE, FALSE) AS is_current_year,
        COALESCE(fiscal_year = current_fiscal_year, FALSE) AS is_current_fiscal_year,

        -- Cumulative cut-off for like-for-like comparisons: every date up to and including the
        -- same day of the previous month (DATEADD clamps to month end, so 31 Mar -> 28/29 Feb)
        COALESCE(date_day <= DATEADD('month', -1, CURRENT_DATE), FALSE) AS is_on_or_before_prior_month_to_date,

        -- Days from today
        DATEDIFF(DAY, date_day, CURRENT_DATE) AS days_from_today

    FROM date_base
)

SELECT *
FROM date_dimension
WHERE date_key < CURRENT_DATE()
ORDER BY date_key
