{{
    config(
        materialized='incremental',
        incremental_strategy='delete+insert',
        unique_key='_source_period',
        on_schema_change='append_new_columns'
    )
}}

{#
  Tabla de hechos de viajes.
  Grano: un viaje válido de Yellow Taxi (una fila por trip_id).
#}

with trips as (

    select *
    from {{ ref('slv_yellow_trips') }}
    {% if is_incremental() %}
    where _source_period in ({{ periods_to_process(ref('slv_yellow_trips')) }})
    {% endif %}

)

select
    -- PK
    trip_id,

    -- FKs a dimensiones
    cast(to_char(pickup_datetime, 'YYYYMMDD') as integer)                    as pickup_date_key,
    hour(pickup_datetime) * 100 + minute(pickup_datetime)                    as pickup_time_key,
    cast(to_char(dropoff_datetime, 'YYYYMMDD') as integer)                   as dropoff_date_key,
    hour(dropoff_datetime) * 100 + minute(dropoff_datetime)                  as dropoff_time_key,
    pickup_location_id                                                       as pickup_location_key,
    dropoff_location_id                                                      as dropoff_location_key,
    vendor_id                                                                as vendor_key,
    rate_code_id                                                             as rate_code_key,
    payment_type_id                                                          as payment_type_key,

    -- atributos degenerados
    pickup_datetime,
    dropoff_datetime,
    is_store_and_forward,
    request_source,

    -- métricas
    passenger_count,
    trip_distance,
    trip_duration_minutes,
    case when trip_duration_minutes > 0
         then round(trip_distance / (trip_duration_minutes / 60), 2) end    as avg_speed_mph,
    fare_amount,
    extra_amount,
    mta_tax_amount,
    tip_amount,
    tolls_amount,
    improvement_surcharge_amount,
    congestion_surcharge_amount,
    airport_fee_amount,
    cbd_congestion_fee_amount,
    total_amount,

    -- linaje
    _source_period,
    _loaded_at

from trips
