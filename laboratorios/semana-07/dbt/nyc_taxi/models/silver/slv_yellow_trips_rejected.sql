{{ config(materialized='view') }}

-- Silver: registros descartados con el motivo, para auditoría de calidad de datos.
select *
from {{ ref('slv_yellow_trips_staged') }}
where rejection_reason is not null
