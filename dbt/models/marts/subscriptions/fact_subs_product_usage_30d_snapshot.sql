{{ config(
    materialized='table',
    tags=['subscriptions', 'piano'],
) }}

WITH active_subscribers AS (
        SELECT user_id, subscription_started_at, subscription_ended_at
        FROM dim_subscription
    ),

    page_views AS (
        SELECT
            s.user_id, s.subscription_started_at, s.subscription_ended_at,
            e.* EXCLUDE (user_id)
        FROM active_subscribers s
        JOIN sdp_silver.studios_piano.studios_piano_events e
            ON s.user_id = e.user_id
            AND e.event_time >= s.subscription_started_at
            AND (e.event_time < s.subscription_ended_at OR s.subscription_ended_at IS NULL)
        WHERE site_id IN (638824, 644938, 644937)
            AND event_time::DATE >= DATEADD(DAY, -60, CURRENT_DATE())
            AND event_name = 'page.display'
            AND geo_country IN ('United states', 'Canada')   -- verify casing
            AND app_type IN ('responsive', 'mobile-app')
    ),

        --     WHEN (content_type = 'article' AND content_pillar = 'News') THEN 'Viewed News Article'
        -- WHEN (content_type = 'video' AND content_pillar = 'News') THEN 'Viewed News Video'

    product_usage AS (
        SELECT
            IFF(event_time::DATE >= DATEADD(DAYS, -30, CURRENT_DATE()), 0, -1) AS period,
            COUNT(DISTINCT IFF(app_type = 'mobile-app', user_id, NULL)) AS mobile_app_users,
            COUNT(DISTINCT IFF(site_id = '644937' AND content_type = 'live-coverage', user_id, NULL)) AS live_news_users,
            COUNT(DISTINCT IFF(site_id = '638824' AND content_pillar = 'Watch-live-news', user_id, NULL)) AS live_news_stream_users,
            COUNT(DISTINCT IFF(STARTSWITH(page, 'sport') OR STARTSWITH(page, 'football'), user_id, NULL)) AS sport_users,
            COUNT(DISTINCT IFF(STARTSWITH(page, 'audio'), user_id, NULL)) AS audio_users,
            COUNT(DISTINCT IFF(site_id = '638824' AND content_type IN ('docs-series', 'docs-episode'), user_id, NULL)) AS docs_users,
            COUNT(DISTINCT IFF(site_id = '638824' AND content_type IN ('article', 'video')
                               AND content_pillar IN ('Business','Innovation','Culture','Future',
                                                      'Future Planet','Travel','Worklife'), user_id, NULL)) AS features_users,
            COUNT(DISTINCT IFF(site_id = '638824' AND content_type IN ('article', 'video') AND content_pillar = 'News', user_id, NULL)) AS news_users,
            COUNT(DISTINCT user_id) AS total_users
        FROM page_views
        GROUP BY 1
    ),

    pct_long AS (
        SELECT period, product, pct
        FROM (
            SELECT
                period,
                mobile_app_users / total_users AS "International App",
                live_news_users  / total_users AS "Live News Pages",
                live_news_stream_users  / total_users AS "Live News Stream",
                sport_users      / total_users AS "Sport",
                audio_users      / total_users AS "Audio",
                docs_users       / total_users AS "Docs",
                features_users   / total_users AS "Features",   -- see note: this is FEATURES logic
                news_users       / total_users AS "News"
            FROM product_usage
        )
        UNPIVOT INCLUDE NULLS (pct FOR product IN (
            "International App","Live News Pages","Live News Stream","Sport","Audio","Docs","Features","News"
        ))
    )

    SELECT
        product,
        current_pct,
        prior_pct,
        (current_pct - prior_pct) / NULLIF(prior_pct, 0) AS mom
    FROM (
        SELECT
            product,
            MAX(IFF(period = 0,  pct, NULL)) AS current_pct,
            MAX(IFF(period = -1, pct, NULL)) AS prior_pct
        FROM pct_long
        GROUP BY product
    )
