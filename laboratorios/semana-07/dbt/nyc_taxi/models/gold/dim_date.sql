-- Dimensión fecha: una fila por día calendario. PK: date_key (YYYYMMDD).
with spine as (

    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="cast('" ~ var('dim_date_start') ~ "' as date)",
        end_date="dateadd(day, 1, cast('" ~ var('dim_date_end') ~ "' as date))"
    ) }}

)

select
    cast(to_char(s.date_day, 'YYYYMMDD') as integer)    as date_key,
    cast(s.date_day as date)                             as full_date,
    year(s.date_day)                                     as year,
    quarter(s.date_day)                                  as quarter,
    month(s.date_day)                                    as month,
    to_char(s.date_day, 'MMMM')                          as month_name,
    to_char(s.date_day, 'YYYY-MM')                       as year_month,
    day(s.date_day)                                      as day_of_month,
    dayofweekiso(s.date_day)                             as day_of_week,      -- 1 = lunes
    dayname(s.date_day)                                  as day_name,
    weekiso(s.date_day)                                  as week_of_year,
    dayofweekiso(s.date_day) in (6, 7)                   as is_weekend,
    h.holiday_date is not null                           as is_holiday,
    h.holiday_name
from spine as s
left join {{ ref('us_holidays') }} as h
    on cast(s.date_day as date) = h.holiday_date
