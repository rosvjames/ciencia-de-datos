-- Silver: catálogo de zonas con nombres estandarizados ('N/A' / vacío -> 'Unknown').
select
    cast(location_id as integer)                                   as location_id,
    coalesce(nullif(nullif(trim(borough), ''), 'N/A'), 'Unknown')      as borough,
    coalesce(nullif(nullif(trim(zone), ''), 'N/A'), 'Unknown')         as zone,
    coalesce(nullif(nullif(trim(service_zone), ''), 'N/A'), 'Unknown') as service_zone
from {{ ref('brz_taxi_zones') }}
