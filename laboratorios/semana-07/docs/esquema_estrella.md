# Esquema estrella (capa GOLD)

**Grano de `fct_trips`:** un viaje válido de NYC Yellow Taxi (una fila por `trip_id`).

```mermaid
erDiagram
    FCT_TRIPS }o--|| DIM_DATE : "pickup_date_key / dropoff_date_key"
    FCT_TRIPS }o--|| DIM_TIME : "pickup_time_key / dropoff_time_key"
    FCT_TRIPS }o--|| DIM_LOCATION : "pickup_location_key / dropoff_location_key"
    FCT_TRIPS }o--|| DIM_VENDOR : vendor_key
    FCT_TRIPS }o--|| DIM_RATE_CODE : rate_code_key
    FCT_TRIPS }o--|| DIM_PAYMENT_TYPE : payment_type_key

    FCT_TRIPS {
        varchar trip_id PK "hash de atributos del viaje"
        int pickup_date_key FK
        int pickup_time_key FK
        int dropoff_date_key FK
        int dropoff_time_key FK
        int pickup_location_key FK
        int dropoff_location_key FK
        int vendor_key FK
        int rate_code_key FK
        int payment_type_key FK
        timestamp pickup_datetime "degenerado"
        timestamp dropoff_datetime "degenerado"
        boolean is_store_and_forward "degenerado"
        varchar request_source "degenerado"
        int passenger_count "métrica"
        number trip_distance "métrica (mi)"
        number trip_duration_minutes "métrica"
        number avg_speed_mph "métrica"
        number fare_amount "métrica USD"
        number extra_amount "métrica USD"
        number mta_tax_amount "métrica USD"
        number tip_amount "métrica USD"
        number tolls_amount "métrica USD"
        number improvement_surcharge_amount "métrica USD"
        number congestion_surcharge_amount "métrica USD"
        number airport_fee_amount "métrica USD"
        number cbd_congestion_fee_amount "métrica USD"
        number total_amount "métrica USD"
        varchar _source_period "linaje"
        timestamp _loaded_at "linaje"
    }

    DIM_DATE {
        int date_key PK "YYYYMMDD"
        date full_date
        int year
        int quarter
        int month
        varchar month_name
        varchar year_month
        int day_of_month
        int day_of_week "1 = lunes"
        varchar day_name
        int week_of_year
        boolean is_weekend
        boolean is_holiday
        varchar holiday_name
    }

    DIM_TIME {
        int time_key PK "HHMM"
        int hour
        int minute
        varchar time_label
        varchar day_part
        boolean is_rush_hour
    }

    DIM_LOCATION {
        int location_key PK "LocationID TLC"
        varchar borough
        varchar zone
        varchar service_zone
        boolean is_airport
    }

    DIM_VENDOR {
        int vendor_key PK
        varchar vendor_name
    }

    DIM_RATE_CODE {
        int rate_code_key PK
        varchar rate_code_name
    }

    DIM_PAYMENT_TYPE {
        int payment_type_key PK
        varchar payment_type_name
    }
```

## Decisiones de modelado

| Elemento | Decisión |
|----------|----------|
| Grano | Un viaje. Es el nivel más atómico que entrega TLC, así se puede agregar a cualquier nivel (hora, día, zona, proveedor) sin perder información. |
| PK del hecho | `trip_id`: hash (`dbt_utils.generate_surrogate_key`) de todos los atributos del viaje. TLC no entrega un ID; el hash es determinista, así re-ejecutar produce la misma llave. |
| PKs de dimensiones | Llaves naturales enteras y estables: `date_key` = YYYYMMDD, `time_key` = HHMM, `location_key` = LocationID, códigos TLC para vendor/rate/payment. Son legibles y no dependen del orden de carga. |
| Role-playing | `dim_date`, `dim_time` y `dim_location` se usan dos veces (pickup y dropoff), sin duplicar tablas. |
| Miembros "Unknown" | `vendor_key = 99`, `rate_code_key = 99` y `payment_type_key = 5` absorben nulos y códigos fuera de catálogo; así toda FK es `not_null` y cumple `relationships`. |
| `dim_time` a nivel minuto | 1.440 filas; permite analizar por hora, franja del día u hora pico sin tocar el hecho. |
| Atributos degenerados | Timestamps exactos, `is_store_and_forward` y `request_source` se quedan en el hecho porque no tienen atributos descriptivos propios. |
| Métricas aditivas | Montos, distancia, duración y pasajeros son sumables; `avg_speed_mph` es no aditiva (se promedia). |
