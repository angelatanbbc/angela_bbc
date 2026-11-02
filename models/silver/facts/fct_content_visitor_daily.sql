    {{
    config(
        materialized='incremental',
        incremental_strategy='delete+insert',
        unique_key='date_key',
        cluster_by=['date_key'],
        on_schema_change='append_new_columns',
        contract={'enforced': true}
    )
}}

/*
  Visitor-day rollup: one row per
    date × visitor × content item × AV item × country × device type × app
  with page views and AV session counts. Built from fct_page_views and fct_av__sessions.

  Why it keeps the visitor: unique visitors can't be added across days or filters.
  Keeping visitor_key lets sv_content count COUNT(DISTINCT visitor_key) correctly for
  any period or cut, on a table far smaller than the raw events. No distinct counts
  are stored here.

  How the two facts fit together:
    - page-view rows have av_content_id = null
    - AV rows carry both content_id (the page the player was on) and av_content_id
      (the video or audio item), so the same row answers "visitors to this article"
      and "views of this video". Video vs audio comes from int_av__metadata at query time.
    - every measure is additive, so sums over any cut equal the facts
      (tests/reconciliation checks this per day)

  Incremental: deletes and rebuilds the last rollup_lookback_days (default 3) of
  dates, the same window fct_av__sessions rebuilds.
*/

{% set lookback = var('rollup_lookback_days', var('av_sessions_lookback_days', 3)) %}
{% set grain = ['date_key', 'visitor_key', 'content_id', 'av_content_id', 'geo_country', 'device_type', 'app_name'] %}

with

{% if is_incremental() %}
refresh_window as (
    select dateadd(day, -{{ lookback }}, max(date_key)) as refresh_from
    from {{ this }}
),
{% endif %}

page_view_rows as (
    select
        to_date(event_time)              as date_key,
        visitor_key,
        content_id,
        null::varchar                    as av_content_id,
        geo_country,
        device_type,
        app_name,
        page_display_event_count         as page_views,
        0 as av_sessions, 0 as av_playbacks, 0 as av_complete_playbacks, 0 as av_plays,
        0 as av_playback_seconds, 0 as av_content_seconds_consumed,
        0 as av_completion_rate_sum, 0 as av_completion_rate_sessions
    from {{ ref('fct_page_views') }}
    {% if is_incremental() %}
    where to_date(event_time) >= (select refresh_from from refresh_window)
    {% endif %}
),

av_rows as (
    select
        session_start_date                                  as date_key,
        visitor_key,
        content_id,
        av_content_id,
        geo_country,
        device_type,
        app_name,
        0                                                   as page_views,
        1                                                   as av_sessions,
        iff(is_playback, 1, 0)                              as av_playbacks,
        iff(is_complete_playback, 1, 0)                     as av_complete_playbacks,
        av_plays,
        coalesce(av_playback_total_duration, 0)             as av_playback_seconds,
        coalesce(av_content_time_consumed, 0)               as av_content_seconds_consumed,
        -- for the old "average completion rate of sessions with a rate above 0"
        iff(av_playback_completion_rate > 0, av_playback_completion_rate, 0) as av_completion_rate_sum,
        iff(av_playback_completion_rate > 0, 1, 0)          as av_completion_rate_sessions
    from {{ ref('fct_av__sessions') }}
    {% if is_incremental() %}
    where session_start_date >= (select refresh_from from refresh_window)
    {% endif %}
),

all_rows as (
    select * from page_view_rows
    union all
    select * from av_rows
)

select
    date_key::date                               as date_key,
    visitor_key::varchar                         as visitor_key,
    content_id::varchar                          as content_id,
    av_content_id::varchar                       as av_content_id,
    geo_country::varchar                         as geo_country,
    device_type::varchar                         as device_type,
    app_name::varchar                            as app_name,
    sum(page_views)::number                      as page_views,
    sum(av_sessions)::number                     as av_sessions,
    sum(av_playbacks)::number                    as av_playbacks,
    sum(av_complete_playbacks)::number           as av_complete_playbacks,
    sum(av_plays)::number                        as av_plays,
    sum(av_playback_seconds)::float              as av_playback_seconds,
    sum(av_content_seconds_consumed)::float      as av_content_seconds_consumed,
    sum(av_completion_rate_sum)::float           as av_completion_rate_sum,
    sum(av_completion_rate_sessions)::number     as av_completion_rate_sessions
from all_rows
group by {{ range(1, grain | length + 1) | join(', ') }}