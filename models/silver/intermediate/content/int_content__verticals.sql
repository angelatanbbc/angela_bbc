{{ 
    config(
        materialized='table',
        tags=['silver','int','content','metadata']
        )
}}

/*
  One row per content item x vertical.

  The rules live in seeds/mappings/vertical_rules.csv. Each row of the
  seed is one condition. How a rule matches:
    - conditions in the same condition_group are OR'd
    - a rule matches only if EVERY one of its condition_groups has a hit (AND)
    - if several rules match, the lowest priority wins, the same as a CASE's first WHEN

  Outputs:
    vertical           the winning vertical ('Unclassified' if no rule matched)
    vertical_rule_id   which rule won, so any categorisation can be explained
    matched_verticals  every vertical whose rule matched, ignoring priority. Use this
                       for "is it Business?" questions, where a Travel article with a
                       Business pillar should still count (the Business baseline does).
*/

with content as (
    select
        page,
        content_id,
        url,
        -- normalise the '$' / '&' encoding artefact once, so the seed lists each name once
        replace(content_section, '$', '&') as content_section,
        replace(content_pillar,  '$', '&') as content_pillar,
        replace(content_topic,   '$', '&') as content_topic
    from {{ ref('int_article__metadata') }}
),

rules as (
    select rule_id, priority, vertical, condition_group, field, match_type, pattern
    from {{ ref('vertical_rules') }}
    where is_active
),

evaluated as (
    select
        c.page,
        c.content_id,
        r.rule_id,
        r.priority,
        r.vertical,
        r.condition_group,
        r.match_type,
        r.pattern,
        case r.field
            when 'page'            then c.page
            when 'url'             then c.url
            when 'content_section' then c.content_section
            when 'content_pillar'  then c.content_pillar
            when 'content_topic'   then c.content_topic
        end as value
    from content c
    cross join rules r
),

condition_hits as (
    select
        *,
        coalesce(
            case match_type
                when 'equals'     then value = pattern
                when 'like'       then value like pattern
                when 'ilike'      then value ilike pattern
                when 'startswith' then startswith(value, pattern)
            end,
            false
        ) as is_hit
    from evaluated
),

group_hits as (   -- OR within a condition group
    select page, rule_id, priority, vertical, condition_group,
           boolor_agg(is_hit) as group_hit
    from condition_hits
    group by 1, 2, 3, 4, 5
),

rule_hits as (    -- AND across a rule's condition groups
    select page, rule_id, priority, vertical
    from group_hits
    group by 1, 2, 3, 4
    having booland_agg(group_hit)
),

winner as (       -- lowest priority wins, like the first matching WHEN
    select page, vertical, rule_id
    from rule_hits
    qualify row_number() over (partition by page order by priority, rule_id) = 1
),

all_matches as (
    select page,
           array_agg(distinct vertical) within group (order by vertical) as matched_verticals
    from rule_hits
    group by 1
)

select
    c.content_id,
    c.page,
    coalesce(w.vertical, 'Unclassified')               as vertical,
    w.rule_id                                          as vertical_rule_id,
    coalesce(a.matched_verticals, array_construct())   as matched_verticals
from content c
left join winner      w on w.page = c.page
left join all_matches a on a.page = c.page
