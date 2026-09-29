{#
  Devuelve los períodos (YYYY-MM) cuyo _loaded_at en el origen es más reciente
  que el ya materializado en el modelo actual ({{ this }}), o que aún no existen.
  Se usa como filtro de los modelos incrementales delete+insert por período:
  si un mes se re-ingesta, se reemplaza completo; si no cambió, no se toca.
#}
{% macro periods_to_process(source_relation) %}
    select src._source_period
    from (
        select _source_period, max(_loaded_at) as loaded_at
        from {{ source_relation }}
        group by 1
    ) as src
    left join (
        select _source_period, max(_loaded_at) as loaded_at
        from {{ this }}
        group by 1
    ) as tgt
        on src._source_period = tgt._source_period
    where tgt.loaded_at is null
       or src.loaded_at > tgt.loaded_at
{% endmacro %}
