{#-
    Schema naming for a multi-developer team.

    prod:          bronze / silver / gold            (clean names consumers query)
    dev, ci, PRs:  <target schema>_bronze / _silver / _gold
                   e.g. dev_sang_gold, ci_pr_42_gold — every developer and every PR is isolated,
                   so nobody can overwrite prod or each other's work.
-#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- elif target.name == 'prod' -%}
        {{ custom_schema_name | trim }}
    {%- else -%}
        {{ target.schema }}_{{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
