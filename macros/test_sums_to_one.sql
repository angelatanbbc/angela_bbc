{#
    Fails for each group whose column does not add up to one, e.g. a conversion whose
    attribution credit is lost or double counted.
#}
{% test sums_to_one(model, column_name, group_by) %}
    SELECT
        {{ group_by }},
        SUM({{ column_name }}) AS total
    FROM {{ model }}
    GROUP BY {{ group_by }}
    HAVING ABS(SUM({{ column_name }}) - 1) > 0.0001
{% endtest %}
