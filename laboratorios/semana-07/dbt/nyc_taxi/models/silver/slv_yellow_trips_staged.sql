{{
    config(
        materialized='incremental',
        incremental_strategy='delete+insert',
        unique_key='_source_period',
        on_schema_change='append_new_columns'
    )
}}

{#
  Silver (staging completo): todos los registros de Bronze tipados, con nombres
  estandarizados, códigos conformados a los catálogos y un rejection_reason
  que es NULL cuando el registro es válido.

  Incremental por período: solo se reprocesan los meses re-ingestados en RAW
  (ver macro periods_to_process). Cada período se reemplaza completo
  (delete+insert), por lo que re-ejecutar no genera duplicados.
#}

with source as (

    select *
    from {{ ref('brz_yellow_tripdata') }}
    {% if is_incremental() %}
    where _source_period in ({{ periods_to_process(ref('brz_yellow_tripdata')) }})
    {% endif %}

),

-- 1. Tipos de datos + nombres consistentes (snake_case descriptivo) --------------
standardized as (

    select
        cast(vendorid as integer)                               as vendor_id,
        cast(tpep_pickup_datetime as timestamp_ntz)             as pickup_datetime,
        cast(tpep_dropoff_datetime as timestamp_ntz)            as dropoff_datetime,
        cast(passenger_count as integer)                        as passenger_count,
        cast(trip_distance as number(10, 2))                    as trip_distance,
        cast(ratecodeid as integer)                             as rate_code_id,
        upper(trim(store_and_fwd_flag))                         as store_and_fwd_flag,
        cast(pulocationid as integer)                           as pickup_location_id,
        cast(dolocationid as integer)                           as dropoff_location_id,
        cast(payment_type as integer)                           as payment_type_id,
        cast(fare_amount as number(10, 2))                      as fare_amount,
        cast(extra as number(10, 2))                            as extra_amount,
        cast(mta_tax as number(10, 2))                          as mta_tax_amount,
        cast(tip_amount as number(10, 2))                       as tip_amount,
        cast(tolls_amount as number(10, 2))                     as tolls_amount,
        cast(improvement_surcharge as number(10, 2))            as improvement_surcharge_amount,
        cast(congestion_surcharge as number(10, 2))             as congestion_surcharge_amount,
        cast(airport_fee as number(10, 2))                      as airport_fee_amount,
        cast(cbd_congestion_fee as number(10, 2))               as cbd_congestion_fee_amount,
        cast(total_amount as number(10, 2))                     as total_amount,
        nullif(upper(trim(request_source)), '')                 as request_source,
        _source_file,
        _source_period,
        _loaded_at
    from source

),

-- 2. Identificador del viaje: hash de todos los atributos de negocio --------------
--    Dos filas con exactamente los mismos valores son el mismo viaje (duplicado).
identified as (

    select
        {{ dbt_utils.generate_surrogate_key([
            'vendor_id', 'pickup_datetime', 'dropoff_datetime', 'passenger_count',
            'trip_distance', 'rate_code_id', 'store_and_fwd_flag',
            'pickup_location_id', 'dropoff_location_id', 'payment_type_id',
            'fare_amount', 'extra_amount', 'mta_tax_amount', 'tip_amount',
            'tolls_amount', 'improvement_surcharge_amount',
            'congestion_surcharge_amount', 'airport_fee_amount',
            'cbd_congestion_fee_amount', 'total_amount', 'request_source'
        ]) }} as trip_id,
        *
    from standardized

),

-- 3. Valores nulos y códigos fuera de catálogo -----------------------------------
conformed as (

    select
        i.trip_id,
        coalesce(v.vendor_id, 99)                               as vendor_id,
        i.pickup_datetime,
        i.dropoff_datetime,
        -- 0 pasajeros no es un valor real: se trata como desconocido (NULL), no se imputa
        case when i.passenger_count > 0 then i.passenger_count end as passenger_count,
        i.trip_distance,
        coalesce(r.rate_code_id, 99)                            as rate_code_id,
        case i.store_and_fwd_flag when 'Y' then true when 'N' then false end
                                                                as is_store_and_forward,
        i.pickup_location_id,
        i.dropoff_location_id,
        coalesce(p.payment_type_id, 5)                          as payment_type_id,
        i.fare_amount,
        -- recargos ausentes = no se cobró el recargo
        coalesce(i.extra_amount, 0)                             as extra_amount,
        coalesce(i.mta_tax_amount, 0)                           as mta_tax_amount,
        coalesce(i.tip_amount, 0)                               as tip_amount,
        coalesce(i.tolls_amount, 0)                             as tolls_amount,
        coalesce(i.improvement_surcharge_amount, 0)             as improvement_surcharge_amount,
        coalesce(i.congestion_surcharge_amount, 0)              as congestion_surcharge_amount,
        coalesce(i.airport_fee_amount, 0)                       as airport_fee_amount,
        coalesce(i.cbd_congestion_fee_amount, 0)                as cbd_congestion_fee_amount,
        i.total_amount,
        i.request_source,
        round(datediff('second', i.pickup_datetime, i.dropoff_datetime) / 60, 2)
                                                                as trip_duration_minutes,
        pz.location_id is not null                              as is_known_pickup_location,
        dz.location_id is not null                              as is_known_dropoff_location,
        i._source_file,
        i._source_period,
        i._loaded_at
    from identified as i
    left join {{ ref('vendors') }}          as v  on i.vendor_id = v.vendor_id
    left join {{ ref('rate_codes') }}       as r  on i.rate_code_id = r.rate_code_id
    left join {{ ref('payment_types') }}    as p  on i.payment_type_id = p.payment_type_id
    left join {{ ref('taxi_zone_lookup') }} as pz on i.pickup_location_id = pz.location_id
    left join {{ ref('taxi_zone_lookup') }} as dz on i.dropoff_location_id = dz.location_id

),

-- 4. Registros inválidos y duplicados --------------------------------------------
validated as (

    select
        *,
        case
            when pickup_datetime is null or dropoff_datetime is null
                then 'missing_timestamp'
            when date_trunc('month', pickup_datetime) != to_date(_source_period || '-01')
                then 'pickup_outside_file_period'
            when dropoff_datetime <= pickup_datetime
                then 'non_positive_duration'
            when trip_duration_minutes > {{ var('max_trip_duration_minutes') }}
                then 'duration_over_limit'
            when trip_distance is null or trip_distance < 0
                then 'invalid_distance'
            when trip_distance > {{ var('max_trip_distance_miles') }}
                then 'distance_over_limit'
            when total_amount is null or total_amount <= 0
                then 'non_positive_total_amount'
            when fare_amount is null or fare_amount < 0
                then 'negative_fare_amount'
            when not is_known_pickup_location or not is_known_dropoff_location
                then 'unknown_location'
            when row_number() over (
                     partition by trip_id
                     order by _loaded_at desc, _source_file
                 ) > 1
                then 'duplicate'
        end as rejection_reason
    from conformed

)

select * from validated
