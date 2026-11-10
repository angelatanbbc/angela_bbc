{#
    The lower bound of a Piano C1X score bucket, such as RevOps or LTS ('95-100%' -> 95, '00-04%' -> 0);
    NULL when unscored.
#}
{% macro parse_score_lower_bound(column) %}
    TRY_TO_NUMBER(SPLIT_PART(REGEXP_REPLACE({{ column }}, '[^0-9-]', ''), '-', 1))
{% endmacro %}
