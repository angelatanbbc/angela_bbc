{{
    config(
        materialized="table",
        tags=["newsletter", "fct"]
    )
}}

WITH signups AS (

    SELECT
        e.*,
        LOWER(TRIM(t.value::VARCHAR)) AS newsletter_key
    FROM {{ ref('int_piano__newsletter_events') }} e,
        LATERAL FLATTEN(input => e.newsletter_title) t
    WHERE e.event_name = 'newsletter.subscribe'

),

newsletters AS (

    SELECT
        newsletter_key,
        newsletter_title
    FROM {{ ref('dim_newsletter') }}

),

visits AS (

    SELECT
        visit_id,
        at_link_origin,
        at_format,
        account_status,
        is_suspected_automated
    FROM {{ ref('fct_newsletter_page_visits') }}

),

first_signed_in AS (

    SELECT
        visitor_id,
        MIN(event_time) AS first_signed_in_at
    FROM {{ ref('int_piano__newsletter_events') }}
    WHERE
        event_name = 'page.display'
        AND user_id IS NOT NULL
    GROUP BY visitor_id

)

SELECT
    {{ dbt_utils.generate_surrogate_key(['s.event_id', 's.newsletter_key']) }} AS newsletter_signup_sk,
    {{ dbt_utils.generate_surrogate_key(['s.newsletter_key']) }} AS newsletter_sk,
    s.event_id,
    s.event_time AS signup_at,
    s.event_date,
    s.visit_id,
    s.visitor_id,
    s.user_id,
    n.newsletter_title,
    s.src,
    s.src_detail,
    s.src_format,
    s.src_medium,
    s.src_campaign,
    LOWER(TRIM(s.src_bbc_team)) AS src_bbc_team,
    s.src_ptr_name,
    v.at_link_origin,
    v.at_format,
    s.device_platform_id,
    s.browser_group,
    s.geo_id,
    s.geo_country,
    -- a sign-up whose visit had no page display of the newsletters page takes the same rule at its own time
    COALESCE(
        v.account_status,
        CASE
            WHEN s.user_id IS NOT NULL AND fs.first_signed_in_at < s.event_time THEN 'Signed in'
            WHEN fs.first_signed_in_at < s.event_time THEN 'Account, not signed in'
            ELSE 'Not identified'
        END
    ) AS account_status,
    COALESCE(v.is_suspected_automated, FALSE) AS is_suspected_automated,
    ROW_NUMBER() OVER (
        PARTITION BY s.visitor_id, s.newsletter_key ORDER BY s.event_time DESC
    ) = 1 AS is_latest_for_visitor_title,
    IFF(
        s.user_id IS NULL,
        FALSE,
        ROW_NUMBER() OVER (PARTITION BY s.user_id, s.newsletter_key ORDER BY s.event_time DESC) = 1
    ) AS is_latest_for_user_title
FROM signups s
INNER JOIN newsletters n
    ON s.newsletter_key = n.newsletter_key
LEFT JOIN visits v
    ON s.visit_id = v.visit_id
LEFT JOIN first_signed_in fs
    ON s.visitor_id = fs.visitor_id
