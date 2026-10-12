{% macro generate_app_type_id(column_name='app_type') %}
    CASE
        WHEN {{ column_name }} IS NULL THEN md5('Unknown')
        WHEN LOWER({{ column_name }}) IN ('responsive', 'mobile-responsive') THEN md5('Web')
        WHEN LOWER({{ column_name }}) = 'mobile-app' THEN md5('Mobile App')
        ELSE md5('Other')
    END
{% endmacro %}
