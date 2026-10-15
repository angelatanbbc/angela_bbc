{#
    The lower bound of Piano's RevOps score bucket ('95-100%' -> 95, '00-04%' -> 0); NULL when unscored.
#}
{% macro parse_ro_lower_bound(column) %}
    TRY_TO_NUMBER(SPLIT_PART(REGEXP_REPLACE({{ column }}, '[^0-9-]', ''), '-', 1))
{% endmacro %}
