{# filter for piano site ids #}
{% macro filter_piano_site_ids(column='site_id') %}
    {{ column }} IN (
        SELECT site_id
        FROM {{ ref('site_id_mapping') }}
        WHERE is_active = true
    )
{% endmacro %}