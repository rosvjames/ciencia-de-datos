{#
  Bronze: los datos tal cual llegan de TLC (mismos nombres y valores),
  más la metadata de linaje: archivo de origen, período y fecha de carga.
#}
select
    vendorid,
    tpep_pickup_datetime,
    tpep_dropoff_datetime,
    passenger_count,
    trip_distance,
    ratecodeid,
    store_and_fwd_flag,
    pulocationid,
    dolocationid,
    payment_type,
    fare_amount,
    extra,
    mta_tax,
    tip_amount,
    tolls_amount,
    improvement_surcharge,
    total_amount,
    congestion_surcharge,
    airport_fee,
    cbd_congestion_fee,
    request_source,

    -- metadata de linaje
    _source_file,
    regexp_substr(_source_file, '[0-9]{4}-[0-9]{2}') as _source_period,
    _loaded_at

from {{ source('raw', 'yellow_tripdata') }}
