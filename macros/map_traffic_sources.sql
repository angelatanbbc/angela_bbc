-- map traffic sources
{% macro map_traffic_source(src_column) %}
    CASE
        WHEN LOWER({{ src_column }}) = 'direct traffic' THEN 'Direct traffic'
        WHEN LOWER({{ src_column }}) = 'search engines' THEN 'Search engines'
        WHEN LOWER({{ src_column }}) LIKE '%social%' THEN 'Social'
        WHEN LOWER({{ src_column }}) = 'referrer sites' THEN 'Referrer sites'
        WHEN LOWER({{ src_column }}) = 'emails' THEN 'Newsletters'
        ELSE 'Other'
    END
{% endmacro %}