{#
    A backfill range from a pair of date vars, as {'start': 'YYYY-MM-DD', 'end': 'YYYY-MM-DD'}
    (end exclusive), or none when neither var is set. Both must be YYYY-MM-DD dates, start
    before end. Used by piano_page_view_backfill_range and attribution_batch_window.
#}
{% macro backfill_date_range(start_var, end_var) %}
    {%- set start = var(start_var, none) -%}
    {%- set end = var(end_var, none) -%}
    {%- if start is none and end is none -%}
        {{ return(none) }}
    {%- endif -%}
    {%- if start is none or end is none -%}
        {{ exceptions.raise_compiler_error("Set both " ~ start_var ~ " and " ~ end_var ~ ", or neither.") }}
    {%- endif -%}
    {%- set start = start | string -%}
    {%- set end = end | string -%}
    {%- if not modules.re.match('^\d{4}-\d{2}-\d{2}$', start) or not modules.re.match('^\d{4}-\d{2}-\d{2}$', end) -%}
        {{ exceptions.raise_compiler_error(start_var ~ " and " ~ end_var ~ " must be YYYY-MM-DD dates.") }}
    {%- endif -%}
    {%- if start >= end -%}
        {{ exceptions.raise_compiler_error(start_var ~ " must be before " ~ end_var ~ " (end is exclusive).") }}
    {%- endif -%}
    {{ return({'start': start, 'end': end}) }}
{% endmacro %}
