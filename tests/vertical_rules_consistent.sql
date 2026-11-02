-- Fails if a rule_id has more than one priority or vertical: a typo that would
-- silently split one rule into two.
select rule_id
from {{ ref('vertical_rules') }}
group by rule_id
having count(distinct priority) > 1 or count(distinct vertical) > 1
