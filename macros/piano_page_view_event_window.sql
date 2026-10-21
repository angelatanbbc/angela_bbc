{#
    Event-time window for the incremental page view models. Renders AND-predicates
    to append to a WHERE clause over Piano events.

    - backfill: when the vars piano_backfill_start and piano_backfill_end are set
      (dates, end exclusive), only that range is processed, replacing the dev and
      incremental windows. Used to build history in bounded chunks: each chunk is
      merged into the existing table (or creates it on the first chunk), so never
      combine these vars with --full-refresh. See the section
      "Backfilling the Piano page view models" in the DNS Transformations Runbook.
    - dev: only the last 30 days of events, so the nightly dev rebuild stays cheap.
    - incremental runs: reprocess from the day before the latest date already
      loaded. Rows are merged on pageview_id, so a page view whose events straddle
      the window boundary keeps the aggregate from its most recent run.

    event_time_column:    event timestamp column of the model's input
    watermark_column:     timestamp column of the model itself used as the high-water mark
    backfill_upper_bound: set false for inputs whose timestamp can fall after the
                          page view's own time (e.g. a page view's last event of any
                          kind), so a backfill chunk keeps their later rows
#}
{% macro piano_page_view_event_window(event_time_column='event_time', watermark_column='last_event_time', backfill_upper_bound=true) %}
    {%- set backfill = piano_page_view_backfill_range() -%}
    {% if backfill %}
        AND {{ event_time_column }} >= '{{ backfill.start }}'::DATE
        {% if backfill_upper_bound %}
            AND {{ event_time_column }} < '{{ backfill.end }}'::DATE
        {% endif %}
    {% else %}
        {% if target.name == 'dev' %}
            AND {{ event_time_column }} >= DATEADD(DAY, -30, CURRENT_DATE)
        {% endif %}
        {% if is_incremental() %}
            AND {{ event_time_column }}::DATE >= (SELECT DATEADD(DAY, -1, MAX({{ watermark_column }})::DATE) FROM {{ this }})
        {% endif %}
    {% endif %}
{% endmacro %}


{#
    incremental_predicates for the page view models' MERGE, so it scans only the
    recent end of the target instead of the whole table. Restricts the target to
    page views at most two days before the window start (page.display events of
    one page view span well under a day), and to the chunk's range on a backfill.

    page_view_time_column: page view timestamp of the target
    watermark_column:      the same high-water mark column passed to piano_page_view_event_window
#}
{% macro piano_page_view_merge_predicates(page_view_time_column='page_view_time', watermark_column='last_event_time') %}
    {%- set backfill = piano_page_view_backfill_range() -%}
    {%- set dest = 'DBT_INTERNAL_DEST.' ~ page_view_time_column -%}
    {%- if backfill -%}
        {{ return([
            dest ~ " >= DATEADD(DAY, -2, '" ~ backfill.start ~ "'::DATE)",
            dest ~ " < DATEADD(DAY, 2, '" ~ backfill.end ~ "'::DATE)"
        ]) }}
    {%- else -%}
        {{ return([
            dest ~ " >= (SELECT DATEADD(DAY, -3, MAX(" ~ watermark_column ~ ")::DATE) FROM " ~ this ~ ")"
        ]) }}
    {%- endif -%}
{% endmacro %}


{#
    The backfill range from the vars piano_backfill_start and piano_backfill_end,
    or none when neither is set. Both must be YYYY-MM-DD dates, start before end.
#}
{% macro piano_page_view_backfill_range() %}
    {%- set start = var('piano_backfill_start', none) -%}
    {%- set end = var('piano_backfill_end', none) -%}
    {%- if start is none and end is none -%}
        {{ return(none) }}
    {%- endif -%}
    {%- if start is none or end is none -%}
        {{ exceptions.raise_compiler_error("Set both piano_backfill_start and piano_backfill_end, or neither.") }}
    {%- endif -%}
    {%- set start = start | string -%}
    {%- set end = end | string -%}
    {%- if not modules.re.match('^\d{4}-\d{2}-\d{2}$', start) or not modules.re.match('^\d{4}-\d{2}-\d{2}$', end) -%}
        {{ exceptions.raise_compiler_error("piano_backfill_start and piano_backfill_end must be YYYY-MM-DD dates.") }}
    {%- endif -%}
    {%- if start >= end -%}
        {{ exceptions.raise_compiler_error("piano_backfill_start must be before piano_backfill_end (end is exclusive).") }}
    {%- endif -%}
    {{ return({'start': start, 'end': end}) }}
{% endmacro %}
