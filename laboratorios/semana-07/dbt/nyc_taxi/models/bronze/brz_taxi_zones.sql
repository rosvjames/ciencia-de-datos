-- Bronze: catálogo de zonas TLC tal cual el CSV oficial (cargado como seed).
select
    location_id,
    borough,
    zone,
    service_zone,
    'taxi_zone_lookup.csv' as _source_file
from {{ ref('taxi_zone_lookup') }}
