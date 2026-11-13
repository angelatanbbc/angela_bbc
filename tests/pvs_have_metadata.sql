-- Fails when a page in fct_page_views has no metadata or no vertical:
-- the models cover different date ranges, or weren't rebuilt together.
select f.page,
       (m.page is null) as missing_metadata,
       (v.page is null) as missing_vertical
from (select distinct page from {{ ref('fct_page_views') }}) f
left join {{ ref('int_article__metadata') }} m on m.page = f.page
left join {{ ref('int_content__verticals') }}   v on v.page = f.page
where m.page is null or v.page is null