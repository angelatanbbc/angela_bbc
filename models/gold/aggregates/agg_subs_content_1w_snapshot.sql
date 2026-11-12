{{
    config(
        materialized='table',
        tags=['subscriptions', 'piano', 'mart', 'reporting']
    )
}}

WITH active_subscribers AS (
    
        SELECT user_first_party_id, subscription_started_at, subscription_ended_at
        FROM {{ ref('dim_subscription') }}
    
    ),
    
    subscriber_events AS (
    
        SELECT
            s.user_first_party_id,
            e.* EXCLUDE (user_first_party_id)
        FROM active_subscribers s
        JOIN {{ source('studios_piano', 'studios_piano_events') }} e
            ON s.user_first_party_id = e.user_first_party_id
            AND e.event_time >= s.subscription_started_at
            AND e.event_time < COALESCE(s.subscription_ended_at, '9999-12-31'::TIMESTAMP)
        WHERE
            site_id IN (638824, 644938, 644937)
            AND event_time >= DATEADD(DAY, -7, CURRENT_DATE())
            AND event_name = 'page.display'
            AND geo_country IN ('United states', 'Canada')   -- verify casing
            AND app_type IN ('responsive', 'mobile-app')
            AND content_type = 'article'
            AND content_id IS NOT NULL
            AND content_pillar IS NOT NULL
            
    ),

    top_title AS (

        SELECT
            content_id,
            content_pillar,
            page_title,
            COUNT(*) AS n_pageviews
        FROM subscriber_events
        GROUP BY content_id, content_pillar, page_title
        -- Piano sends a few page views with no title; prefer the most viewed real title.
        QUALIFY ROW_NUMBER() OVER (
            PARTITION BY content_id
            ORDER BY page_title IS NULL ASC, n_pageviews DESC, page_title ASC
        ) = 1
    
    ),

    untitled_content AS (

        SELECT content_id
        FROM top_title
        WHERE page_title IS NULL

    ),

    -- Some pages (such as the 2026 election results pages) send their subscriber article
    -- views without a title, so fall back to the most common title on any page view.
    fallback_title AS (

        SELECT
            e.content_id,
            e.page_title,
            COUNT(*) AS n_pageviews
        FROM {{ source('studios_piano', 'studios_piano_events') }} e
        JOIN untitled_content u
            ON e.content_id = u.content_id
        WHERE
            e.event_time >= DATEADD(DAY, -7, CURRENT_DATE())
            AND e.event_name = 'page.display'
            AND e.page_title IS NOT NULL
        GROUP BY e.content_id, e.page_title
        QUALIFY ROW_NUMBER() OVER (
            PARTITION BY e.content_id
            ORDER BY n_pageviews DESC, e.page_title ASC
        ) = 1

    ),

    counts AS (
    
        SELECT
            content_id,
            COUNT(DISTINCT user_first_party_id) AS subscribers_viewed,
            COUNT(*) AS article_views
        FROM subscriber_events
        GROUP BY content_id

    )

    SELECT
        c.content_id,
        t.content_pillar,
        COALESCE(t.page_title, f.page_title) AS page_title,
        c.subscribers_viewed,
        c.article_views
    FROM counts c
    JOIN top_title t
        ON c.content_id = t.content_id
    LEFT JOIN fallback_title f
        ON c.content_id = f.content_id
    ORDER BY subscribers_viewed DESC
