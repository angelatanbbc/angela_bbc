{#
    The LTS (likelihood to subscribe) tier of a parsed lower bound; 'No score' when NULL.
#}
{% macro lts_band(column) %}
    CASE
        WHEN {{ column }} >= 90 THEN 'LTS 90+'
        WHEN {{ column }} >= 70 THEN 'LTS 70-89'
        WHEN {{ column }} >= 40 THEN 'LTS 40-69'
        WHEN {{ column }} >= 20 THEN 'LTS 20-39'
        WHEN {{ column }} >= 0 THEN 'LTS 0-19'
        ELSE 'No score'
    END
{% endmacro %}
