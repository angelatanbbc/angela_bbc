{{ 
    config(
        materialized='table',
        tags=['int','av','metadata']) }}

/*
  One row per AV content item (av_content_id)
  Built from av_properties_ranked, av_content_duration_range_ranked

    - duration, content type, broadcasting type and genre are picked TOGETHER,
      as one combination: complete beats popular (a combination with a duration
      beats any without one, then type, broadcasting type, genre), then the most
      sessions, then a tie-break so the result is repeatable
    - duration range is picked on its own the same way
    - titles, show, episode, brands and genre names come from VMB (one row per
      av_content_id after staging)

  Which sessions count towards the pick (vars):
    av_metadata_start / av_metadata_end   session start dates, both inclusive
                                          (default: every session in fct_av__sessions)
*/

{% set start_date     = var('content_start_date', none) %}
{% set end_date       = var('content_end_date', none) %}

with all_sessions as (
    select
        av_content_id,
        session_start_time,
        av_session_content_duration,
        av_content_type,
        av_broadcasting_type,
        av_content_genre,
        av_content_duration_range,
        true
        {% if start_date %} and session_start_date >= '{{ start_date }}' {% endif %}
        {% if end_date %}   and session_start_date <= '{{ end_date }}'   {% endif %}
            as counts_for_pick
    from {{ ref('fct_av__sessions') }}
    where av_content_id is not null
),


all_content as (   -- every item, so UK-only items still get their VMB titles
    select distinct av_content_id 
    from all_sessions
),

ranking_sessions as (
    select
        av_session_id,
        session_start_time,
        av_content_id,
        av_session_content_duration,
        av_content_type,
        av_broadcasting_type,
        av_content_genre,
        av_content_duration_range
    from all_sessions-- sessions used for the pick; not a reporting metric
    where counts_for_pick

),

properties_ranked as (
    select
        av_content_id,
        av_session_content_duration,
        av_content_type,
        av_broadcasting_type,
        av_content_genre,
        sum(count(*)) over (partition by av_content_id) as av_sessions_count -- all of the item's sessions in the window
    from ranking_sessions
    group by 1, 2, 3, 4, 5
    qualify row_number() over (
        partition by av_content_id
        order by (av_session_content_duration is null),
                 (av_content_type is null),
                 (av_broadcasting_type is null),
                 (av_content_genre is null),
                 count(*) desc,                  -- one row per session, so this is sessions
                 max(session_start_time) desc,   -- tie-breaks added so the result is repeatable
                 av_session_content_duration,
                 av_content_type,
                 av_broadcasting_type,
                 av_content_genre
    ) = 1
),

duration_range_ranked as (
    select
        av_content_id,
        av_content_duration_range
    from ranking_sessions
    group by 1, 2
    qualify row_number() over (
        partition by av_content_id
        order by (av_content_duration_range is null),
                 count(*) desc,
                 max(session_start_time) desc,
                 av_content_duration_range
    ) = 1
)

select
    c.av_content_id,
    -- piano
    p.av_session_content_duration,      -- length of the content
    p.av_content_type,                  -- Video or Audio
    p.av_broadcasting_type,             -- Clip, Live, Ondemand
    p.av_content_genre,
    d.av_content_duration_range,        -- e.g. sfv-vertical
    -- VMB enrichment
    v.av_clip_title,
    v.av_show,
    v.av_episode,
    v.av_brand_title,
    v.av_master_brand_name,
    v.av_pips_genre_level_1_names,
    coalesce(s.av_sessions_count, 0) as av_sessions -- sessions used for metadata selection; not a reporting metric
from all_content c
left join properties_ranked     p on p.av_content_id = c.av_content_id
left join duration_range_ranked d on d.av_content_id = c.av_content_id
left join  {{ source('vmb__av_enrichment', 'av_enrichment') }} v on v.av_content_id = c.av_content_id