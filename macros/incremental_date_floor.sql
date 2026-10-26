{#
    Earliest date an incremental run reprocesses: the latest date of `column` already loaded minus
    `days_back`, or none on a full build. Returned as a literal date rather than a subquery so
    Snowflake can prune the scan of the Piano events.
#}
{% macro incremental_date_floor(column, days_back=1) %}
    {% if is_incremental() and execute %}
        {% set latest = run_query('SELECT MAX(' ~ column ~ ')::DATE FROM ' ~ this).columns[0].values()[0] %}
        {% if latest is not none %}
            {{ return(latest - modules.datetime.timedelta(days=days_back)) }}
        {% endif %}
    {% endif %}
    {{ return(none) }}
{% endmacro %}
