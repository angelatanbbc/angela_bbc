{{ config(severity='warn') }}

-- Warns about active rules that never win for any content item: either dead
-- (the section or page was renamed) or fully shadowed by a higher-priority rule.
select r.rule_id, r.vertical
from (select distinct rule_id, vertical from {{ ref('vertical_rules') }} where is_active) r
left join (select distinct vertical_rule_id from {{ ref('int_content__verticals') }}) v
  on v.vertical_rule_id = r.rule_id
where v.vertical_rule_id is null
