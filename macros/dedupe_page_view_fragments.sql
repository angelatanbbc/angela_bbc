{#
    Merges page views that a chunked backfill split into two or more rows, in
    int_piano__page_views and fct_page_views. Run it after a backfill and before its tests:

        dbt run-operation dedupe_page_view_fragments --target <target>

    Why the split happens: chunks run newest month first, and each chunk's MERGE only looks at
    target rows within two days of the chunk (piano_page_view_merge_predicates). A page view
    whose page.display events straddle a month boundary, with the later ones more than two days
    into the next month, gets one row per chunk, each holding only its own month's events.

    The fragments of a page view hold disjoint sets of events, so they merge exactly, as the
    model would have built them from all the events at once:
    - descriptive attributes from the fragment with the latest event
    - page_view_time and page_view_time_utc (and page_view_date) from the earliest fragment
    - page_duration the largest, page_display_event_count the sum
    The scroll, click, ad and duration measures of fct_page_views come from page-view-grain
    models, so every fragment already carries the same values and they need no change.

    dry_run=true only reports the counts.
#}
{% macro dedupe_page_view_fragments(dry_run=false) %}
    {%- if not execute -%}
        {{ return(none) }}
    {%- endif -%}

    {%- do merge_page_view_fragments(
        ref('int_piano__page_views'),
        latest_column='last_event_time',
        merged_columns=[
            ('MIN(page_view_time)', 'page_view_time'),
            ('MIN(page_view_time_utc)', 'page_view_time_utc'),
            ('MAX(page_duration)', 'page_duration'),
            ('SUM(page_display_event_count)', 'page_display_event_count'),
        ],
        dry_run=dry_run
    ) -%}
    {%- do merge_page_view_fragments(
        ref('fct_page_views'),
        latest_column='page_view_time',
        merged_columns=[
            ('MIN(page_view_time)', 'page_view_time'),
            ('MIN(page_view_time_utc)', 'page_view_time_utc'),
            ('MIN(page_view_time)::DATE', 'page_view_date'),
            ('MAX(page_duration_seconds)', 'page_duration_seconds'),
            ('SUM(page_display_event_count)', 'page_display_event_count'),
        ],
        dry_run=dry_run
    ) -%}
{% endmacro %}


{#
    Merges the rows that share a pageview_id in one table into a single row, in one
    transaction: the merged rows go into a temporary table, every fragment is deleted and the
    merged rows are inserted.

    relation:       the table
    latest_column:  orders the fragments; the latest one gives the descriptive attributes
    merged_columns: (aggregate expression, column) pairs that replace that fragment's values
#}
{% macro merge_page_view_fragments(relation, latest_column, merged_columns, dry_run=false) %}
    {%- set merged = (relation.identifier if relation.identifier is defined else relation | string | replace('.', '_'))
        ~ '__merged_fragments' -%}

    {%- set merged_sql -%}
        CREATE OR REPLACE TEMPORARY TABLE {{ merged }} AS
        WITH fragments AS (

            SELECT
                pageview_id,
                {%- for expression, column in merged_columns %}
                {{ expression }} AS {{ column }},
                {%- endfor %}
                COUNT(*) AS fragment_count
            FROM {{ relation }}
            GROUP BY pageview_id
            HAVING COUNT(*) > 1

        )

        SELECT
            p.* REPLACE (
                {%- for expression, column in merged_columns %}
                f.{{ column }} AS {{ column }}{{ ',' if not loop.last }}
                {%- endfor %}
            ),
            f.fragment_count
        FROM {{ relation }} p
        INNER JOIN fragments f
            ON p.pageview_id = f.pageview_id
        QUALIFY ROW_NUMBER() OVER (PARTITION BY p.pageview_id ORDER BY p.{{ latest_column }} DESC) = 1
    {%- endset -%}

    {%- do run_query(merged_sql) -%}
    {%- set counts = run_query(
        'SELECT COUNT(*), COALESCE(SUM(fragment_count), 0) FROM ' ~ merged
    ) -%}
    {%- set page_views = counts.columns[0].values()[0] -%}
    {%- set fragment_rows = counts.columns[1].values()[0] -%}

    {%- if page_views == 0 -%}
        {%- do log(relation ~ ': no split page views', info=true) -%}
    {%- elif dry_run -%}
        {%- do log(relation ~ ': ' ~ page_views ~ ' page views split into ' ~ fragment_rows
            ~ ' rows (dry run, nothing changed)', info=true) -%}
    {%- else -%}
        {%- do run_query('BEGIN') -%}
        {%- do run_query(
            'DELETE FROM ' ~ relation ~ ' WHERE pageview_id IN (SELECT pageview_id FROM ' ~ merged ~ ')'
        ) -%}
        {%- do run_query('INSERT INTO ' ~ relation ~ ' SELECT * EXCLUDE (fragment_count) FROM ' ~ merged) -%}
        {%- do run_query('COMMIT') -%}
        {%- do log(relation ~ ': merged ' ~ fragment_rows ~ ' rows into ' ~ page_views ~ ' page views', info=true) -%}
    {%- endif -%}

    {%- do run_query('DROP TABLE IF EXISTS ' ~ merged) -%}
{% endmacro %}
