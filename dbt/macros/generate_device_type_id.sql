{% macro generate_device_type_id(column_name='device_type') %}
    CASE
        WHEN {{ column_name }} IS NULL THEN md5('Unknown')
        WHEN LOWER({{ column_name }}) = 'mobile phone' THEN md5('Mobile Phone')
        WHEN LOWER({{ column_name }}) = 'desktop' THEN md5('Desktop')
        WHEN LOWER({{ column_name }}) = 'tablet' THEN md5('Tablet')
        ELSE md5('Other')
    END
{% endmacro %}
