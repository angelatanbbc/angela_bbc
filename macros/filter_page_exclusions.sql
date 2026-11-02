{# filter excluded pages #}
{% macro filter_page_exclusions(page='page') %}
    {{ page }} NOT IN (
        SELECT page
        FROM {{ ref('page_exclusions') }}
    )
{% endmacro %}