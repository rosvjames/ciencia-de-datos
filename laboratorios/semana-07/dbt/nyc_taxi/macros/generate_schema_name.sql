{#
  Usa exactamente el esquema configurado (BRONZE / SILVER / GOLD) en lugar
  del comportamiento por defecto de dbt (<target_schema>_<custom_schema>).
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim | upper }}
    {%- endif -%}
{%- endmacro %}
