# Diagrama de arquitectura

```mermaid
flowchart LR
    subgraph TLC["NYC TLC (fuente)"]
        PQ["yellow_tripdata_YYYY-MM.parquet<br/>(CloudFront, 20 meses)"]
    end

    subgraph DOCKER["Docker Compose (local)"]
        direction TB
        LOADER["flow-loader<br/>(importa flujos vía API)"]
        subgraph KESTRA["Kestra v1.3.37"]
            direction TB
            P["nyc_taxi.pipeline"]
            B["nyc_taxi.backfill<br/>ForEach x20, concurrencia 4"]
            I["nyc_taxi.ingest_month<br/>1. Download<br/>2. Upload (PUT)<br/>3. DELETE + COPY INTO"]
            IR["nyc_taxi.init_raw<br/>DDL IF NOT EXISTS"]
            D["nyc_taxi.dbt_build<br/>dbt deps + dbt build"]
            P --> B --> I
            B --> IR
            P --> D
        end
        KDB[("Postgres<br/>metadata Kestra")]
        DBT["Proyecto dbt<br/>(montado en /dbt)"]
        LOADER --> KESTRA
        KESTRA --- KDB
        D -.usa.-> DBT
    end

    subgraph SF["Snowflake · DB NYC_TAXI · WH NYC_TAXI_WH"]
        direction LR
        STG[/"@RAW.TLC_STAGE<br/>archivos Parquet"/]
        RAW[("RAW<br/>YELLOW_TRIPDATA<br/>+ _source_file, _loaded_at")]
        BRZ[("BRONZE<br/>brz_yellow_tripdata<br/>brz_taxi_zones + seeds")]
        SLV[("SILVER<br/>slv_yellow_trips_staged<br/>slv_yellow_trips<br/>slv_yellow_trips_rejected<br/>slv_taxi_zones")]
        GLD[("GOLD<br/>fct_trips<br/>dim_date · dim_time · dim_location<br/>dim_vendor · dim_rate_code · dim_payment_type")]
        STG -->|COPY INTO| RAW --> BRZ --> SLV --> GLD
    end

    PQ -->|HTTP GET| I
    I -->|PUT| STG
    I -->|COPY INTO| RAW
    D -->|SQL| BRZ
    D -->|SQL| SLV
    D -->|SQL + tests| GLD
```

## Flujo de datos

| Paso | Componente | Qué hace | Idempotencia |
|------|-----------|----------|--------------|
| 1 | `init_raw` | Crea esquema RAW, file format Parquet, stage interno y tabla raw | `CREATE ... IF NOT EXISTS` |
| 2 | `ingest_month` → Download | Descarga el Parquet del mes al storage de Kestra | — |
| 3 | `ingest_month` → Upload | `PUT` al stage `@RAW.TLC_STAGE/yellow/` | Sobrescribe el archivo |
| 4 | `ingest_month` → Queries | `DELETE` de las filas del archivo + `COPY INTO ... FORCE=TRUE` en una transacción | El mes se reemplaza completo |
| 5 | `dbt_build` → Bronze | Vistas sobre RAW con metadata de linaje (`_source_file`, `_source_period`, `_loaded_at`) | Vistas |
| 6 | `dbt_build` → Silver | Tipado, estandarización, nulos, códigos, deduplicación, reglas de invalidez | Incremental `delete+insert` por período |
| 7 | `dbt_build` → Gold | Esquema estrella (`fct_trips` + 6 dimensiones) | Tablas / incremental `delete+insert` por período |
| 8 | `dbt_build` → Tests | 88 tests (not_null, unique, relationships, accepted_values, expression_is_true, reconciliaciones) | — |
