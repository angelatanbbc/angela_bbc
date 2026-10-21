WITH base_events AS (
    SELECT
        event_time,
        site_id,
        visitor_id,
        visit_id,
        geo_country,
        page,
        content_id,
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
    FROM SDP_SILVER.STUDIOS_PIANO.STUDIOS_PIANO_EVENTS bbc
    WHERE to_date(event_time) = date('2026-09-30')
    --between date'2026-09-01' and date('2026-09-30')
    -->= '2026-09-01T00:00:00' AND event_time < '2026-10-01T00:00:00'
      AND site_id IN (638823, --legacy data before feb 2025
            638824, -- BBCS_BBC
            644937, -- legacy news after feb 2025
            644938, -- legacy sport after feb 2025
            646755, -- legacy weather
            646752, -- legacy features
            643247, -- storyworks
            646753) -- news langauges
      AND geo_country <> 'United kingdom'
      --geo_country in ('United states', 'Canada', 'Jamaica', 'Barbados', 'Grenada', 'Haiti', 'Bahamas', 'Trinidad and tobago', 'Saint lucia', 'Saint kitts and nevis', 'Saint vincent and the grenadines', 'Antigua and barbuda') 
      AND event_name = 'page.display'
      AND page NOT IN ( 'keepalive', 'page.view.page', 'onboarding.page' , 'error.page' , 'notification.page', 'page.page', 'promptbeta.page', 'action_before_pageview.page', 'searchpage.page', 'pages.privacy_policy.page', 'pages.terms_of_use.page')
      and not startswith(page, 'id')
      AND (NOT COALESCE(app_name, '') ILIKE ANY ('%uk%','%chrysalis%'))
)
-- picking the combination of content sections, content topic, content pillar with the most page views 
,page_metadata_ranked AS (
    SELECT
        page,
        case when page in ('home.page', 'news.page', 'sport.page') THEN null else content_section end as content_section,
        case when page in ('home.page', 'news.page', 'sport.page') THEN null else content_topic end as content_topic,
        case when page in ('home.page', 'news.page', 'sport.page') THEN null else content_pillar end as content_pillar,
        url, 
        COUNT(*) AS pvs,
        ROW_NUMBER() OVER (
            PARTITION BY page
            ORDER BY (content_section is null), -- picks the first non null value for each property, otherwise null
                     (content_topic is null),
                     (content_pillar is null),
                     (url is NULL), COUNT(*) DESC -- orders by descending page views 
        ) AS rn
    FROM base_events
    WHERE site_id not in (646755, 643247, 646753)
    GROUP BY
        page,
        content_section,
        content_topic,
        content_pillar,
        url
    QUALIFY rn = 1
)
, content_id as (
    SELECT page, content_id, count(*) as pvs, ROW_NUMBER() OVER (PARTITION BY page ORDER BY pvs DESC) as rn
    FROM base_events
    WHERE content_id is not null
    GROUP BY page, content_id
    QUALIFY rn = 1
)
, content_type as (
    SELECT page, content_type, count(*) as pvs, ROW_NUMBER() OVER (PARTITION BY page ORDER BY pvs DESC) as rn
    FROM base_events
    WHERE content_type is not null
    GROUP BY page, content_type
    QUALIFY rn = 1
)
-- one row per content metadata, since it duplicates rows when there are updates 
, seo_metadata as (
      SELECT id, 
        max(path) as path,
        max(title) as title, 
        max(summary) as summary, 
        max(type) as type, 
        max(subtype) as subtype,
        min(first_published_at) as first_published_at,
        max(last_published_at) as last_published_at
    FROM SDP_BRONZE.CONTENT_METADATA_SEO.BBC_CONTENT_METADATA
    group by id
    order by id
)
-- gets page title and publication date 
,page_pub_date AS (
    SELECT
        page,
        date_published, page_title, 
        COUNT(*) AS pvs,
        ROW_NUMBER() OVER (
            PARTITION BY page
            ORDER BY COUNT(*) DESC
        ) AS rn
    FROM base_events
    GROUP BY
        page, date_published, page_title
    QUALIFY rn = 1
)
-- assigning vertical 
, page_categories AS (
    SELECT DISTINCT
        b.page,
        CASE
            WHEN page = 'home.page' THEN 'Home page'
            WHEN page = 'news.page' THEN 'News front'
            WHEN startswith(b.page, 'sport') THEN 'Sport'
            WHEN startswith(b.page, 'audio') THEN 'Audio' 
            WHEN startswith(b.page, 'video.doc') THEN 'Docs' 
            
            WHEN ((content_section in ('Travel', 'The Travel Show', 'The SpeciaList', 'Discover the World') 
            or content_pillar = 'Travel' 
            or url like '%bbc.com/travel%' 
            or content_topic ilike any ('%Travel%', '%Remote Places%', '%World''s Table%', '%Food $ Drink%', '%Food & Drink%')) 
            AND (startswith(b.page, 'travel.') or startswith(b.page, 'reel')))  THEN 'Travel'

            WHEN (content_section = 'Business' 
            or content_pillar = 'Business' 
            or content_topic ilike any ('%business%', '%Opening Bell%')
            or startswith(b.page, 'news.business') 
            or b.page = 'business.page' or url like '%bbc.com/business%')
                THEN 'Business'

            WHEN (content_pillar = 'Health' or content_section in ('Science $ Health', 'Science & Health', 'Family $ Education', 'Family & Education') or content_topic ilike any ('%health%', '%wellbeing%', '%medicine%', '%psychology%', '%fitness%', '%nutrition%', '%diet%', '%Science $ Health%', '%sleep%', '%mind%', '%love%', '%exercise%', '%longevity%', '%neuroscience%') or b.page = 'health.page' or url like '%bbc.com/health%') 
            THEN 'Health'

            WHEN (content_section in ('Art', 'Art history', 'Arts', 'Arts in Motion', 'Culture', 'Entertainment $ Arts', 'Entertainment & Arts', 'History', 'Film $ TV', 'Film & TV', 'Culture $ Experiences', 'Culture & Experiences', 'Photography') or content_pillar in ('Arts', 'Arts in Motion', 'Culture') or startswith(b.page, 'culture.') or b.page in ('culture.page', 'arts.page') or url like any ('%bbc.com/culture%', '%bbc.com/arts%') or content_topic ilike any ('%Art%', '%Culture%', '%History%', '%Books%', '%Film%'))
                THEN 'Culture'

            WHEN (content_section in ('Earth', 'Climate', 'Science $ Environment', 'Future Planet', 'Science & Environment', 'World of wonder', 'Natural wonders', 'Science') or content_pillar in ('Earth', 'Climate', 'Science $ Environment', 'Science & Environment', 'Future Planet') 
            or content_topic ilike any ('%earth%', '%climate%', '%world of wonder%', '%weather%', '%natural wonders%', '%green living%', '%environment%', '%nature%', '%future planet%', '%sustainability%', '%plants%', '%animals%', '%carbon%', '%global warming%', '%wind power%', '%solar power%', '%pollution%', '%conservation%', '%severe weather%', '%flood%', '%drought%', '%wildfire%', '%heatwave%', '%el nino%', '%tornado%', '% COP %', '%just stop oil%', '%green getaways%', '%eco-tourism%', '%nature & outdoors%', '%space%', '%solar system%', '%science%', '%astronomy%', '%geology%', '%planet%', '% sun, %', '% space,%', '%archaeology%', '%wildlife%') 
            or url = 'https://www.bbc.com/innovation/science' 
            or b.page in ('science.page', 'future_planet.page') 
            or url like '%bbc.com/future-planet%')
                THEN 'Earth & Science'

            WHEN (content_section in ('Technology', 'Tech Now') or content_pillar = 'Technology' or  content_topic ilike any ('%technology%', '%Artificial intelligence%', '%AI v the Mind%', '%Robot%', '%Computer%', '%Data breaches%', '%cyber%', '%gaming%') or b.page in ('technology.page', 'innovation.page') OR url LIKE '%bbc.com/technology%' OR content_pillar = 'Innovation') 
                THEN 'Tech'

            WHEN ((b.page = 'news.us_canada.page' or content_section in ('US $ Canada', 'US & Canada') or page like any ('%us_and_canada%', '%us_canada%')) and startswith(page, 'news'))
            THEN 'US & Canada News'
            
            WHEN ((b.page in ('news.war_in_ukraine.page', 'news.world.europe.page', 'news.world.asia.page', 'news.world.africa.page', 'news.topics.c2vdnvdg6xxt.page', 'news.world.latin_america.page', 'news.world.middle_east.page', 'news.world.australia.page', 'news.in_pictures.page', 'news.bbcindepth.page', 'news.bbcverify.page', 'news.uk.page', 'news.england.page', 'news.scotland.page', 'news.northern_ireland.page', 'news.wales.page', 'news.politics.page', 'news.scotland.scotland_politics.page', 'news.northern_ireland.northern_ireland_politics.page', 'news.wales.wales_politics.page') or content_section in ('Asia', 'Europe', 'World', 'Africa', 'Middle East', 'Australia', 'Latin America', 'BBC InDepth', 'In Pictures', 'Verify', 'Politics', 'Newsbeat', 'Israel-Gaza war', 'War in Ukraine', 'India', 'BBC Verify', 'China', 'UK', 'England', 'Berkshire', 'Scotland') 
            or startswith(b.page, 'news.article') 
            or startswith(b.page, 'news.video') 
            or startswith(b.page, 'news.world') 
            or startswith(b.page, 'news.live') 
            or url like '%bbc.com/world%') and startswith(page, 'news')) 
            THEN 'World News (excludes US&Canada)'
        END AS vertical
        ,
        content_section, 
        content_topic,
        content_pillar,
        url
        
    FROM page_metadata_ranked b
    --JOIN pages_with_pvs p ON b.page = p.page
)   
, final_table as (
SELECT 

-- info about the user, raw piano data 
    a.event_time, 
    a.visitor_id, 
    a.visit_id, 
    a.geo_country, 
    a.site_id, 
    a.src, 
    a.src_url, 
    a.app_type, 

-- content identifiers 
    a.page, -- raw piano 
    e.content_id, -- joined relevant value 

-- metadata 
    seo_metadata.path as seo_path, 
    seo_metadata.title as seo_title,
    seo_metadata.summary as seo_summary,
    seo_metadata.type as seo_type,
    seo_metadata.subtype as seo_subtype,
    seo_metadata.first_published_at,
    seo_metadata.last_published_at, 

-- piano info about the content, joined relevant values 
    d.content_type, 
    b.url, 
    b.vertical, 
    b.content_section, 
    b.content_topic, 
    b.content_pillar, 
    c.page_title, 
    c.date_published
    
FROM base_events a
LEFT JOIN page_categories b on a.page = b.page
LEFT JOIN page_pub_date c on a.page = c.page
LEFT JOIN content_type d on a.page = d.page
LEFT JOIN content_id e on a.page = e.page
LEFT JOIN seo_metadata on e.content_id = seo_metadata.id
WHERE site_id not in (646755, 643247, 646753) --exclude weather, storyworks, newslanguages
)
SELECT page_title, 
    page, 
    vertical,
    content_section, 
    content_pillar, 
    content_topic, 
    content_type, 
    url, 
    date_published, 
    first_published_at, 
    last_published_at,  
    seo_type, 
    seo_subtype,
    
    count(*) as pvs
from final_table
where page like '%article%'
group by 1, 2, 3,4,5,6,7,8,9,10,11, 12, 13
order by pvs desc 
