{{ config(
    materialized='table',
    tags=['subscriptions', 'piano'],
) }}

WITH active_subscribers AS (
    
        SELECT user_id, subscription_started_at, subscription_ended_at
        FROM {{ ref('dim_subscription') }}
    
    ),
    
    subscriber_events AS (
    
        SELECT
            s.user_id,
            e.* EXCLUDE (user_id)
        FROM active_subscribers s
        JOIN {{ source('studios_piano', 'studios_piano_events') }} e
            ON s.user_id = e.user_id
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
        QUALIFY ROW_NUMBER() OVER (PARTITION BY content_id ORDER BY n_pageviews DESC) = 1
    
    ),

    counts AS (
    
        SELECT
            content_id,
            COUNT(DISTINCT user_id) AS subscribers_viewed,
            COUNT(*) AS article_views
        FROM subscriber_events
        GROUP BY content_id

    )

    SELECT
        content_id,
        content_pillar,
        page_title,
        subscribers_viewed,
        article_views
    FROM counts
    JOIN top_title USING (content_id)
    ORDER BY subscribers_viewed DESC
