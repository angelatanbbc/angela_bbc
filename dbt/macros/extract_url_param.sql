{% macro extract_url_param(url_column, param_name) %}
    REGEXP_SUBSTR({{ url_column }}, '{{ param_name }}=([^&]+)', 1, 1, '', 1)
{% endmacro %}
