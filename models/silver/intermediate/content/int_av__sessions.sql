{{
    config(
        materialized='table',
        unique_key='av_session_id',
        incremental_strategy='merge',
        cluster_by=['session_start_date'],
        on_schema_change='append_new_columns',
        contract={'enforced': true}
    )
}}

/*
  Fact: one row per AV session (who watched, where, and how much).
  Built from the "base_av_events" step of the AV dashboard query.
  Formerly fct_media_session.

  What it keeps (and what it leaves to other models):
    - in-scope sites, no junk pages, AV events only
    - UK traffic and UK apps are KEPT, with geo_country and app_name on the row:
      UK is a flag on the dimensions, not a filter in facts. The parity query and
      int_av__metadata apply the old exclusions themselves.
    - content-level properties (VMB titles and brands, the chosen content type,
      genre, duration range) live in int_av__metadata, keyed on av_content_id.
      The av_* properties on this model are as reported on THIS session, and
      are only used to pick the content-level values.

  One row per session:
    - text columns: the first non-null value in the session
    - av_content_time_consumed, av_playback_total_duration, av_playback_completion_rate:
      session totals that Piano repeats on each event, so take the max (the latest total)

  Incremental: each run rebuilds every session that started in the last
  av_sessions_lookback_days (default 3), reading one extra day of events so a
  session that started just before the window is never rebuilt from half its events.
  A session longer than about a day that started before the window keeps its old row.
  fct_content_visitor_daily uses the same lookback, so rebuilt sessions reach it.

  Full refresh window (vars, both dates inclusive):
    av_sessions_start (default 2025-09-01), av_sessions_end (default: up to today)
    Parity with the September query:
      dbt build -s fct_av__sessions --full-refresh
        --vars '{av_sessions_start: 2026-09-01, av_sessions_end: 2026-09-30}'
*/

{% set start_date = var('av_sessions_start', '2025-09-01') %}
{% set end_date   = var('av_sessions_end', none) %}
{% set lookback   = var('av_sessions_lookback_days', 3) %}

{# Columns taken as the first non-null value in the session #}
{% set first_value_columns = [
    'av_content_id', 'content_id', 'page',
    'visitor_id', 'ckns_echo_device_id', 'visit_id',
    'site_id', 'geo_country', 'app_name', 'device_type',
    'av_session_content_duration', 'av_content_type', 'av_broadcasting_type',
    'av_content_genre', 'av_content_duration_range'
] %}

with

{% if is_incremental() %}
refresh_window as (
    select dateadd(day, -{{ lookback }}, max(session_start_date)) as refresh_from
    from {{ this }}
),
{% endif %}

av_events as (
    select
        av_session_id,
        event_time,
        event_name,
        {{ first_value_columns | join(',\n        ') }},
        av_playback_total_duration,
        av_content_time_consumed,
        av_playback_completion_rate
    from {{ ref('stg_piano__studios_events') }}
    where av_session_id is not null
      and {{ filter_piano_site_ids() }}
      and not {{ filter_page_exclusions() }}
      {% if is_incremental() %}
      and to_date(event_time) >= (select dateadd(day, -1, refresh_from) from refresh_window)
      {% else %}
      and to_date(event_time) >= '{{ start_date }}'
      {% if end_date %} and to_date(event_time) <= '{{ end_date }}' {% endif %}
      {% endif %}
),

sessions as (
    select
        av_session_id,
        min(event_time)          as session_start_time,
        to_date(min(event_time)) as session_start_date,
        max(event_time)          as session_end_time,

        {% for col in first_value_columns -%}
        min_by({{ col }}, iff({{ col }} is not null, event_time, null)) as {{ col }},
        {% endfor %}

        max(av_playback_total_duration)  as av_playback_total_duration,
        max(av_content_time_consumed)    as av_content_time_consumed,
        max(av_playback_completion_rate) as av_playback_completion_rate,

        count_if(event_name in ('av.play', 'rm.play')) as av_plays,
        count(*)                                       as av_events
    from av_events
    group by av_session_id
)

select
    -- keys
    av_session_id::varchar                        as av_session_id,
    session_start_date::date                      as session_start_date,
    session_start_time::timestamp_ntz             as session_start_time,
    session_end_time::timestamp_ntz               as session_end_time,
    {{ visitor_key('session_start_date') }}       as visitor_key,
    av_content_id::varchar                        as av_content_id,
    content_id::varchar                           as content_id,
    page::varchar                                 as page,
    site_id::number                               as site_id,
    geo_country::varchar                          as geo_country,
    app_name::varchar                             as app_name,
    device_type::varchar                          as device_type,
    visitor_id::varchar                           as visitor_id,
    ckns_echo_device_id::varchar                  as ckns_echo_device_id,
    visit_id::varchar                             as visit_id,
    -- as reported on this session (for reporting, use int_av__metadata)
    av_session_content_duration::float            as av_session_content_duration,
    av_content_type::varchar                      as av_content_type,
    av_broadcasting_type::varchar                 as av_broadcasting_type,
    av_content_genre::varchar                     as av_content_genre,
    av_content_duration_range::varchar            as av_content_duration_range,
    -- measures
    av_plays::number                              as av_plays,
    av_events::number                             as av_events,
    av_playback_total_duration::float             as av_playback_total_duration,
    av_content_time_consumed::float               as av_content_time_consumed,
    av_playback_completion_rate::float            as av_playback_completion_rate,
    coalesce(av_content_time_consumed > 0, false)                                         as is_playback,
    coalesce(av_content_time_consumed > 0 and av_playback_completion_rate >= 0.95, false) as is_complete_playback
from sessions
{% if is_incremental() %}
where session_start_date >= (select refresh_from from refresh_window)
{% endif %}