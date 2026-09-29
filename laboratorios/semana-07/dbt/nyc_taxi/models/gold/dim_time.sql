-- Dimensión hora del día a nivel minuto (1.440 filas). PK: time_key (HHMM).
with minutes as (

    select row_number() over (order by seq4()) - 1 as minute_of_day
    from table(generator(rowcount => 1440))

)

select
    cast(floor(minute_of_day / 60) * 100 + mod(minute_of_day, 60) as integer) as time_key,
    cast(floor(minute_of_day / 60) as integer)                     as hour,
    cast(mod(minute_of_day, 60) as integer)                        as minute,
    lpad(floor(minute_of_day / 60), 2, '0') || ':' || lpad(mod(minute_of_day, 60), 2, '0')
                                                                   as time_label,
    case
        when floor(minute_of_day / 60) between 0 and 5   then 'Madrugada'
        when floor(minute_of_day / 60) between 6 and 11  then 'Mañana'
        when floor(minute_of_day / 60) between 12 and 17 then 'Tarde'
        else 'Noche'
    end                                                            as day_part,
    floor(minute_of_day / 60) between 7 and 9
        or floor(minute_of_day / 60) between 16 and 19             as is_rush_hour
from minutes
