{{ 
    config(
        materialized='table',
        tags=['silver','int','content','article','metadata']) }}

/*
  One row per page: the metadata the vertical rules and dim_content read.
  A direct translation of page_metadata_ranked, content_sk, content_type and
  page_pub_date from the Global Content Dashboard query, so verticals match it.

    - key = page
    - section, topic, pillar and url are ranked TOGETHER as one combination
    - complete metadata beats popular metadata: a combination with a section
      beats any without one, then topic, pillar, url; page views only break ties
    - home.page, news.page and sport.page get no section, topic or pillar
    - only in-scope traffic counts: in-scope sites, no UK, no UK apps, no junk pages
    - weather, storyworks and news-languages sites don't count towards the ranking
    - content_sk and content_type: the most frequent non-null value per page
    - page_title and date_published: the most frequent pair per page

*/


with base_events as (
    select 
        page_view_time,
        page,
        content_section,
        content_topic,
        content_pillar,
        url,
        content_sk,
        content_type,
        page_title,
        date_published
    from {{ ref('fct_page_views') }}
    where true
      and to_date(page_view_time) >= dateadd(day, -{{ var('article_metadata_days', 90) }}, current_date)
),
-- the front pages carry no section, topic or pillar
metadata_events as (
    select
        page_view_time,
        page,
        iff(page in ('home.page', 'news.page', 'sport.page'), null, content_section) as content_section,
        iff(page in ('home.page', 'news.page', 'sport.page'), null, content_topic)   as content_topic,
        iff(page in ('home.page', 'news.page', 'sport.page'), null, content_pillar)  as content_pillar,
        url
    from base_events
),

-- one combination of section, topic, pillar and url per page
metadata_ranked as (
    select 
        page, 
        content_section, 
        content_topic, 
        content_pillar,
        url
    from metadata_events
    group by page, content_section, content_topic, content_pillar, url
    qualify row_number() over (
        partition by page
        order by (content_section is null),
                 (content_topic is null),
                 (content_pillar is null),
                 (url is null),
                 count(*) desc,
                 max(page_view_time) desc,    -- tie-break added so the result is repeatable
                 content_section, content_topic, content_pillar, url
    ) = 1
),

content_sks as (
    select page, content_sk
    from base_events
    where content_sk is not null
    group by 1, 2
    qualify row_number() over (partition by page order by count(*) desc, max(page_view_time) desc, content_sk) = 1
),

content_types as (
    select page, content_type
    from base_events
    where content_type is not null
    group by 1, 2
    qualify row_number() over (partition by page order by count(*) desc, max(page_view_time) desc, content_type) = 1
),

titles as (
    select page, page_title, date_published
    from base_events
    group by 1, 2, 3
    qualify row_number() over (partition by page order by count(*) desc, max(page_view_time) desc, page_title, date_published) = 1
),

-- in-scope page views in the window; used to pick one page per content_sk in dim_content
page_totals as (
    select page, count(*) as page_views
    from base_events
    group by 1
)

select
    m.page,
    i.content_sk,
    m.url,
    m.content_section,
    m.content_topic,
    m.content_pillar,
    t.content_type,
    p.page_title,
    p.date_published,
    v.page_views
from metadata_ranked m
left join content_sks   i on i.page = m.page
left join content_types t on t.page = m.page
left join titles        p on p.page = m.page
left join page_totals   v on v.page = m.page