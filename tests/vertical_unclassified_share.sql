{{ config(severity='warn') }}

-- Warns when more than 5% of content items fall through every rule.
select count_if(vertical = 'Unclassified') / nullif(count(*), 0) as unclassified_share
from {{ ref('int_content__verticals') }}
having unclassified_share > 0.05
