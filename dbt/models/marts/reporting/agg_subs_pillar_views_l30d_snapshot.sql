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
            AND e.event_time <  COALESCE(s.subscription_ended_at, '9999-12-31'::TIMESTAMP)
        WHERE
            site_id IN (638824, 644938, 644937)
            AND event_time >= DATEADD(DAY, -30, CURRENT_DATE())
            AND event_name = 'page.display'
            AND geo_country in ('United states','Canada')
            AND page != 'keepalive'
            AND page NOT IN (
                'page.page', 'more.page', 'error.page', 'keepalive', 'notification.page',
                'action_before_pageview.page', 'searchpage.page', 'subscribe.page',
                'id.auth_identifier_signin.page'
            )
    
    ),
    
    base_events AS (
    
        SELECT
            to_date(event_time) AS event_date,
            date_trunc('month', to_date(event_time)) AS month,
            page,
            user_id,
            visitor_id,
            visit_id,
            geo_country,
            content_section,
            content_topic,
            content_pillar,
            url,
            content_type,
            app_type,
            src,
            src_url,
            date_published,
            page_title
        FROM subscriber_events
    
    )
    -- picking the combination of content sections with the most page views
    , page_metadata_ranked AS (
        SELECT
            page,
            case when page in ('home.page', 'news.page', 'sport.page') THEN null else content_section end as content_section,
            case when page in ('home.page', 'news.page', 'sport.page') THEN null else content_topic end as content_topic,
            case when page in ('home.page', 'news.page', 'sport.page') THEN null else content_pillar end as content_pillar,
            url,
            COUNT(*) AS pvs,
            ROW_NUMBER() OVER (
                PARTITION BY page
                ORDER BY (content_section is null),
                         (content_topic is null),
                         (content_pillar is null),
                         (url is NULL), COUNT(*) DESC
            ) AS rn
        FROM base_events
        GROUP BY
            page, content_section, content_topic, content_pillar, url
        QUALIFY rn = 1
    )
    , content_type as (
        SELECT page, content_type, count(*) as pvs, ROW_NUMBER() OVER (PARTITION BY page ORDER BY pvs DESC) as rn
        FROM base_events
        GROUP BY page, content_type
        QUALIFY rn = 1
    )
    , page_pub_date AS (
        SELECT
            page, date_published, page_title,
            COUNT(*) AS pvs,
            ROW_NUMBER() OVER (PARTITION BY page ORDER BY COUNT(*) DESC) AS rn
        FROM base_events
        GROUP BY page, date_published, page_title
        QUALIFY rn = 1
    )
    -- assigning vertical
    , page_categories AS (
        SELECT DISTINCT
            b.page,
            CASE
                WHEN page = 'home.page' THEN 'Home page'
                WHEN page = 'news.page' THEN 'News front'
                WHEN startswith(page, 'audio') THEN 'Audio'
                WHEN startswith(page,'video.series') or startswith(page,'video.episode') or page = 'video.docs.page' THEN 'Docs'
                WHEN page = 'watch_live_news.page' then 'Watch Live News'
    
                WHEN ((content_section in ('Travel', 'The Travel Show', 'The SpeciaList') or content_pillar = 'Travel' or url like '%bbc.com/travel%') AND startswith(b.page, 'travel.'))  THEN 'Travel'
    
                WHEN (content_section = 'Business'
                or content_pillar = 'Business'
                or content_topic ilike '%business%'
                or startswith(b.page, 'news.business')
                or b.page = 'business.page' or url like '%bbc.com/business%')
                    THEN 'Business'
    
                WHEN (content_pillar = 'Health' or content_section in ('Science $ Health', 'Science & Health', 'Family $ Education', 'Family & Education') or content_topic ilike any ('%health%', '%wellbeing%', '%medicine%', '%psychology%', '%fitness%', '%nutrition%', '%diet%', '%Science $ Health%', '%sleep%', '%mind%', '%love%', '%exercise%', '%longevity%', '%neuroscience%') or b.page = 'health.page' or url like '%bbc.com/health%')
                THEN 'Health'
    
                WHEN (content_section in ('Arts', 'Arts in Motion', 'Culture', 'Entertainment $ Arts', 'Entertainment & Arts', 'History', 'Film $ TV', 'Film & TV', 'Culture $ Experiences', 'Culture & Experiences', 'Photography') or content_pillar in ('Arts', 'Arts in Motion', 'Culture') or startswith(b.page, 'culture.') or b.page in ('culture.page', 'arts.page') or url like any ('%bbc.com/culture%', '%bbc.com/arts%'))
                    THEN 'Culture'
    
                WHEN (content_section in ('Earth', 'Climate', 'Science $ Environment', 'Future Planet', 'Science & Environment', 'World of wonder', 'Natural wonders', 'Science', 'Discover the World') or content_pillar in ('Earth', 'Climate', 'Science $ Environment', 'Science & Environment', 'Future Planet')
                or content_topic ilike any ('%earth%', '%climate%', '%world of wonder%', '%weather%', '%natural wonders%', '%green living%', '%environment%', '%nature%', '%future planet%', '%sustainability%', '%plants%', '%animals%', '%carbon%', '%global warming%', '%wind power%', '%solar power%', '%pollution%', '%conservation%', '%severe weather%', '%flood%', '%drought%', '%wildfire%', '%heatwave%', '%el nino%', '%tornado%', '% COP %', '%just stop oil%', '%green getaways%', '%eco-tourism%', '%nature & outdoors%', '%space%', '%solar system%', '%science%', '%astronomy%', '%geology%', '%planet%', '% sun, %', '% space,%', '%archaeology%')
                or url = 'https://www.bbc.com/innovation/science'
                or b.page in ('science.page', 'video.docs.category.earth.page', 'future_planet.page')
                or url like '%bbc.com/future-planet%')
                    THEN 'Earth & Science'
    
                WHEN (content_section in ('Technology', 'Tech Now') or content_pillar = 'Technology' or  content_topic ilike any ('%technology%', '%Artificial intelligence%', '% ai,%') or b.page in ('technology.page', 'innovation.page') OR url LIKE '%bbc.com/technology%' OR content_pillar = 'Innovation')
                    THEN 'Tech'
    
                WHEN startswith(b.page, 'sport') THEN 'Sport'
    
                WHEN (b.page in ('news.us_canada.page', 'news.war_in_ukraine.page', 'news.world.europe.page', 'news.world.asia.page', 'news.world.africa.page', 'news.topics.c2vdnvdg6xxt.page', 'news.world.latin_america.page', 'news.world.middle_east.page', 'news.world.australia.page', 'news.in_pictures.page', 'news.bbcindepth.page', 'news.bbcverify.page', 'news.uk.page', 'news.england.page', 'news.scotland.page', 'news.northern_ireland.page', 'news.wales.page', 'news.politics.page', 'news.scotland.scotland_politics.page', 'news.northern_ireland.northern_ireland_politics.page', 'news.wales.wales_politics.page') or content_section in ('Asia', 'Europe', 'World', 'Africa', 'Middle East', 'Australia', 'Latin America', 'BBC InDepth', 'In Pictures', 'Verify', 'US $ Canada', 'US & Canada', 'Politics', 'Newsbeat', 'Israel-Gaza war', 'War in Ukraine', 'India', 'BBC Verify', 'China', 'UK', 'England', 'Berkshire', 'Scotland')
                or startswith(b.page, 'news.article')
                or startswith(b.page, 'news.video')
                or startswith(b.page, 'news.world')
                or startswith(b.page, 'news.live')
                or url like '%bbc.com/world%')
                THEN 'US & World News'
            END AS category,
            content_section, content_topic, content_pillar, url
        FROM page_metadata_ranked b
    )
    , final_table as (
        SELECT a.event_date, a.month, a.page, a.visitor_id, a.visit_id, a.geo_country
        , b.category, b.content_section, b.content_topic, b.content_pillar, b.url, d.content_type
        , c.date_published, c.page_title
        , a.src, a.src_url, a.app_type
        FROM base_events a
        LEFT JOIN page_categories b on a.page = b.page
        LEFT JOIN page_pub_date c on a.page = c.page
        LEFT JOIN content_type d on a.page = d.page
    )
    SELECT category, count(*) as page_views
    FROM final_table
    GROUP BY 1
