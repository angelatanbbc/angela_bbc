{% macro generate_geo_id(geo_country, geo_region) %}
    {{ dbt_utils.generate_surrogate_key([
        "COALESCE(NULLIF(" ~ geo_country ~ ", 'Unknown'), 'Unknown')",
        "COALESCE(NULLIF(" ~ geo_region ~ ", 'Unknown'), 'Unknown')"
    ]) }}
{% endmacro %}