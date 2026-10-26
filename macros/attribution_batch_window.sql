{#
    The conversion_date range an incremental attribution model processes, as
    {'start': 'YYYY-MM-DD', 'end': 'YYYY-MM-DD' or none} (end exclusive), or none at parse time.

    - backfill: when the vars attribution_backfill_start and attribution_backfill_end are set
      (dates, end exclusive), only that range is processed. Used to build history in monthly
      chunks with ops/backfill_page_views.sh --mode attribution; each chunk replaces its
      conversion dates (delete+insert), or creates the table on the first chunk.
    - incremental runs: from the latest conversion_date already loaded minus
      var('attribution_reprocess_days').
    - first build (no table yet, or an empty one): the last var('attribution_initial_build_days')
      days only, so the scheduled run that creates the table stays small. Older history is
      backfilled in chunks.

    Returned as literal dates rather than subqueries so Snowflake can prune the page view scan.
#}
{% macro attribution_batch_window() %}
    {%- set backfill = backfill_date_range('attribution_backfill_start', 'attribution_backfill_end') -%}
    {%- if backfill -%}
        {{ return(backfill) }}
    {%- endif -%}
    {%- if not execute -%}
        {{ return(none) }}
    {%- endif -%}
    {%- if is_incremental() -%}
        {%- set latest = run_query(
            'SELECT DATEADD(DAY, -' ~ var('attribution_reprocess_days') ~ ', MAX(conversion_date))::VARCHAR FROM ' ~ this
        ).columns[0].values()[0] -%}
        {%- if latest is not none -%}
            {{ return({'start': latest, 'end': none}) }}
        {%- endif -%}
    {%- endif -%}
    {%- set initial = run_query(
        'SELECT DATEADD(DAY, -' ~ var('attribution_initial_build_days') ~ ', CURRENT_DATE)::VARCHAR'
    ).columns[0].values()[0] -%}
    {{ return({'start': initial, 'end': none}) }}
{% endmacro %}


{#
    `column` within an attribution_batch_window range, e.g. conversion_date >= '2026-10-01'::DATE
    AND conversion_date < '2026-11-01'::DATE. Pass lookback_days to start that many days earlier
    (for page views that can belong to the window's first journeys).
#}
{% macro attribution_window_predicate(window, column, lookback_days=0) %}
    {%- if lookback_days -%}
        {{ column }} >= DATEADD(DAY, -{{ lookback_days }}, '{{ window.start }}'::DATE)
    {%- else -%}
        {{ column }} >= '{{ window.start }}'::DATE
    {%- endif -%}
    {%- if window.end %} AND {{ column }} < '{{ window.end }}'::DATE{% endif -%}
{% endmacro %}
