{{
    config(
        materialized="table",
        tags=["newsletter", "dim"]
    )
}}

WITH titles AS (

    SELECT
        LOWER(TRIM(t.value::VARCHAR)) AS newsletter_key,
        TRIM(t.value::VARCHAR) AS spelling,
        e.event_time
    FROM {{ ref('int_piano__newsletter_events') }} e,
        LATERAL FLATTEN(input => e.newsletter_title) t
    WHERE e.event_name = 'newsletter.subscribe'

),

-- a title Piano sends in more than one case (How to Sleep Better / How To Sleep Better) takes its most common spelling
names AS (

    SELECT
        newsletter_key,
        spelling AS newsletter_title
    FROM titles
    GROUP BY newsletter_key, spelling
    QUALIFY ROW_NUMBER() OVER (PARTITION BY newsletter_key ORDER BY COUNT(*) DESC, spelling ASC) = 1

)

SELECT
    {{ dbt_utils.generate_surrogate_key(['t.newsletter_key']) }} AS newsletter_sk,
    t.newsletter_key,
    LEFT(n.newsletter_title, 512)::VARCHAR(512) AS newsletter_title,
    MIN(t.event_time) AS first_signup_at,
    MAX(t.event_time) AS last_signup_at,
    COUNT(*) AS signup_rows
FROM titles t
INNER JOIN names n
    ON t.newsletter_key = n.newsletter_key
GROUP BY t.newsletter_key, n.newsletter_title
