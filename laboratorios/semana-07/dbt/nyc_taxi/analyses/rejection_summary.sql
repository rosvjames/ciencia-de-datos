-- Resumen de calidad: registros descartados por motivo y período.
select _source_period, rejection_reason, count(*) as rows_rejected
from {{ ref('slv_yellow_trips_rejected') }}
group by 1, 2
order by 1, 3 desc
