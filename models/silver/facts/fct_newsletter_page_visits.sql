{{
    config(
        materialized="table",
        tags=["newsletter", "fct"]
    )
}}

WITH events AS (

    SELECT *
    FROM {{ ref('int_piano__newsletter_events') }}

),

displays AS (

    SELECT *
    FROM events
    WHERE event_name = 'page.display'

),

latest_display AS (

    SELECT *
    FROM displays
    QUALIFY ROW_NUMBER() OVER (PARTITION BY visit_id ORDER BY event_time DESC) = 1

),

first_signup AS (

    SELECT
        visit_id,
        MIN(event_time) AS first_signup_at
    FROM events
    WHERE event_name = 'newsletter.subscribe'
    GROUP BY visit_id

),

display_summary AS (

    SELECT
        d.visit_id,
        MIN(d.event_time) AS first_display_at,
        MAX(d.event_time) AS last_display_at,
        COUNT(*) AS page_displays,
        MAX(IFF(f.first_signup_at IS NULL OR d.event_time < f.first_signup_at, d.user_id, NULL)) AS user_id
    FROM displays d
    LEFT JOIN first_signup f
        ON d.visit_id = f.visit_id
    GROUP BY d.visit_id

),

first_signed_in AS (

    SELECT
        visitor_id,
        MIN(event_time) AS first_signed_in_at
    FROM displays
    WHERE user_id IS NOT NULL
    GROUP BY visitor_id

),

signups AS (

    SELECT
        e.visit_id,
        COUNT(DISTINCT e.event_id) AS signup_events,
        COUNT(DISTINCT LOWER(TRIM(t.value::VARCHAR))) AS titles_signed_up
    FROM events e,
        LATERAL FLATTEN(input => e.newsletter_title) t
    WHERE e.event_name = 'newsletter.subscribe'
    GROUP BY e.visit_id

)

SELECT
    l.visit_id,
    l.visitor_id,
    a.user_id,
    l.event_date,
    a.first_display_at,
    a.last_display_at,
    a.page_displays,
    l.src,
    l.src_detail,
    l.src_format,
    l.src_medium,
    l.src_campaign,
    LOWER(TRIM(l.src_bbc_team)) AS src_bbc_team,
    l.src_ptr_name,
    l.at_link_origin,
    l.at_format,
    l.device_platform_id,
    l.browser_group,
    l.geo_id,
    l.geo_country,
    CASE
        WHEN a.user_id IS NOT NULL THEN 'Signed in'
        WHEN fs.first_signed_in_at < COALESCE(f.first_signup_at, a.first_display_at) THEN 'Account, not signed in'
        ELSE 'Not identified'
    END AS account_status,
    COALESCE(s.signup_events, 0) AS signup_events,
    COALESCE(s.titles_signed_up, 0) AS titles_signed_up,
    s.visit_id IS NOT NULL AS signed_up,
    a.page_displays > {{ var('newsletter_automated_display_limit') }} AS is_suspected_automated
FROM latest_display l
INNER JOIN display_summary a
    ON l.visit_id = a.visit_id
LEFT JOIN first_signup f
    ON l.visit_id = f.visit_id
LEFT JOIN signups s
    ON l.visit_id = s.visit_id
LEFT JOIN first_signed_in fs
    ON l.visitor_id = fs.visitor_id
