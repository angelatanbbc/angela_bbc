{{ 
    config(
        materialized='table',
        tags=['silver','int','content','page_views']
        )
}}
/*
  One row per page: the metadata the vertical rules and dim_content read.
  A direct translation of page_metadata_ranked, content_id, content_type and
  page_pub_date from the Global Content Dashboard query, so verticals match it.
    - key = page
    - section, topic, pillar and url are ranked TOGETHER as one combination
    - complete metadata beats popular metadata: a combination with a section
      beats any without one, then topic, pillar, url; page views only break ties
    - home.page, news.page and sport.page get no section, topic or pillar
    - only in-scope traffic counts: in-scope sites, no UK, no UK apps, no junk pages
    - weather, storyworks and news-languages sites don't count towards the ranking
    - content_id and content_type: the most frequent non-null value per page
    - page_title and date_published: the most frequent pair per page
  Date window (vars):
    content_start_date / content_end_date
*/

{% set start_date = var('content_start_date') %}
{% set end_date = var('content_end_date', none) %}

select
    event_time,
    site_id,
    page,
    content_id,
    content_section,
    content_topic,
    content_pillar,
    url,
    content_type,
    date_published,
    page_title,
    visitor_id,
    geo_country,
    device_type,
    app_name,
    1::number as page_display_event_count
from {{ source('studios_piano', 'studios_piano_events') }}
where to_date(event_time) >= '{{ start_date }}'
    {% if end_date %} and to_date(event_time) <= '{{ end_date }}' {% endif %}
AND {{ filter_page_exclusions() }}
AND {{ filter_exclude_uk_app_name()}}
AND {{ filter_exclude_url() }}
AND geo_country <> 'United kingdom'
AND {{ filter_piano_site_ids() }}
AND event_name = 'page.display'