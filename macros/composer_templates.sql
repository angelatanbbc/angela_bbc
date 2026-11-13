{#
    The hard subscription paywall as Piano records it on experience.action and vx.conversion events:
    a modal, non-closable 'BBC Subscription' offer. Pass the table alias with its dot, or nothing.
#}
{% macro is_paywall_template(prefix='') %}
    ({{ prefix }}template_display_mode = 'modal'
    AND {{ prefix }}template_closable = FALSE
    AND {{ prefix }}term_offer_name = 'BBC Subscription')
{% endmacro %}

{#
    The inline subscription offer (the landing-page offer BOF campaigns drive to): an in-page,
    non-modal 'BBC Subscription' offer. Not the hard paywall.
#}
{% macro is_offer_template(prefix='') %}
    ({{ prefix }}template_display_mode = 'inline'
    AND {{ prefix }}term_offer_name = 'BBC Subscription')
{% endmacro %}
