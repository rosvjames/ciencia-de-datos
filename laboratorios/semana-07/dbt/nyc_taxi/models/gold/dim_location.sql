-- Dimensión zona TLC (role-playing: origen y destino). PK: location_key (= LocationID TLC).
select
    location_id                                 as location_key,
    borough,
    zone,
    service_zone,
    zone ilike '%airport%'                      as is_airport
from {{ ref('slv_taxi_zones') }}
