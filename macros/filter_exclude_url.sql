{# list of excluded url patterns #}
{% macro excluded_url_patterns() %}
    {{ return([
        '%embed%'
        ]) }}
{% endmacro %}

{# true if the url matches an excluded pattern #}
{% macro is_excluded_url(url='url') %}
coalesce({{ url }}, '') ilike any ('{{ excluded_url_patterns() | join("', '") }}')
{% endmacro %}

{# filter for URLs: must exist and must not be excluded #}
{% macro filter_exclude_url(url='url') %}
    {{ url }} IS NOT NULL
    AND NOT ({{ is_excluded_url(url) }})
{% endmacro %}