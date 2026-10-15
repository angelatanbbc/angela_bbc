{#
    Earliest conversion_date an incremental attribution run rebuilds: the latest date already
    loaded minus var('attribution_reprocess_days'), or none on a full build. Returned as a
    literal date rather than a subquery so Snowflake can prune the page view scan.
#}
{% macro attribution_batch_floor() %}
    {% if is_incremental() and execute %}
        {% set latest = run_query('SELECT MAX(conversion_date) FROM ' ~ this).columns[0].values()[0] %}
        {% if latest is not none %}
            {{ return(latest - modules.datetime.timedelta(days=var('attribution_reprocess_days'))) }}
        {% endif %}
    {% endif %}
    {{ return(none) }}
{% endmacro %}
