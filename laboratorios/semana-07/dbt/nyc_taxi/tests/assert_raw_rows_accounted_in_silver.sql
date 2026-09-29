-- Ninguna fila se pierde entre Bronze y Silver: válidas + rechazadas = filas en Bronze.
with bronze as (
    select _source_period, count(*) as n from {{ ref('brz_yellow_tripdata') }} group by 1
),

silver as (
    select _source_period, count(*) as n from {{ ref('slv_yellow_trips_staged') }} group by 1
)

select b._source_period, b.n as bronze_rows, s.n as silver_rows
from bronze as b
left join silver as s on b._source_period = s._source_period
where s.n is distinct from b.n
