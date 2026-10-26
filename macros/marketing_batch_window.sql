{#
    The visit_date range an incremental marketing model processes, as
    {'start': 'YYYY-MM-DD', 'end': 'YYYY-MM-DD' or none} (end exclusive), or none at parse time.
    The same rules as attribution_batch_window:

    - backfill: when the vars marketing_backfill_start and marketing_backfill_end are set (dates,
      end exclusive), only that range is processed; each run replaces its visit dates.
    - incremental runs: from the latest visit_date already loaded minus var('marketing_reprocess_days').
    - first build (no table yet, or an empty one): the last var('marketing_initial_build_days') days,
      never before var('marketing_start_date'). Older history is backfilled in chunks.
#}
{% macro marketing_batch_window() %}
    {%- set backfill = backfill_date_range('marketing_backfill_start', 'marketing_backfill_end') -%}
    {%- if backfill -%}
        {{ return(backfill) }}
    {%- endif -%}
    {%- if not execute -%}
        {{ return(none) }}
    {%- endif -%}
    {%- if is_incremental() -%}
        {%- set latest = run_query(
            'SELECT DATEADD(DAY, -' ~ var('marketing_reprocess_days') ~ ', MAX(visit_date))::VARCHAR FROM ' ~ this
        ).columns[0].values()[0] -%}
        {%- if latest is not none -%}
            {{ return({'start': latest, 'end': none}) }}
        {%- endif -%}
    {%- endif -%}
    {%- set initial = run_query(
        "SELECT GREATEST(DATEADD(DAY, -" ~ var('marketing_initial_build_days') ~ ", CURRENT_DATE), '"
        ~ var('marketing_start_date') ~ "'::DATE)::VARCHAR"
    ).columns[0].values()[0] -%}
    {{ return({'start': initial, 'end': none}) }}
{% endmacro %}


{#
    The page views that can belong to a marketing_batch_window's visits: from the day before its
    start (visits running over midnight are cut off by visit_date later) to the day after its end.
#}
{% macro marketing_page_view_predicate(window, column) %}
    {%- if window -%}
        {{ column }} >= DATEADD(DAY, -1, '{{ window.start }}'::DATE)
        {%- if window.end %} AND {{ column }} < DATEADD(DAY, 1, '{{ window.end }}'::DATE){% endif -%}
    {%- else -%}
        TRUE
    {%- endif -%}
{% endmacro %}
