{{ config(materialized='view') }}

-- Silver: viajes limpios y válidos (un registro por trip_id).
select * exclude (rejection_reason, is_known_pickup_location, is_known_dropoff_location)
from {{ ref('slv_yellow_trips_staged') }}
where rejection_reason is null
