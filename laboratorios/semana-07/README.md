# Laboratorio Integrador I — ELT NYC Yellow Taxi

Tubería ELT reproducible que ingiere 20 meses de **NYC Yellow Taxi** (enero 2025 – agosto 2026), los carga en **Snowflake** y los transforma con **dbt** en una arquitectura **Bronze → Silver → Gold**. El resultado final es un esquema estrella para analizar los viajes. Todo se orquesta con **Kestra** sobre Docker.

- Diagrama de arquitectura: [`docs/arquitectura.md`](docs/arquitectura.md)
- Diagrama del esquema estrella: [`docs/esquema_estrella.md`](docs/esquema_estrella.md)

## Estructura

```
semana-07/
├── docker-compose.yml          # Kestra + Postgres (metadata) + flow-loader
├── .env.example                # variables de conexión (copiar a .env)
├── kestra/
│   ├── Dockerfile              # imagen Kestra + dbt-snowflake
│   ├── load_flows.sh           # importa los flujos vía API al levantar
│   └── flows/                  # código de ingesta y orquestación
│       ├── nyc_taxi.pipeline.yml       # flujo principal: backfill -> dbt_build
│       ├── nyc_taxi.backfill.yml       # ForEach sobre los 20 meses
│       ├── nyc_taxi.ingest_month.yml   # descarga -> PUT stage -> DELETE + COPY INTO
│       ├── nyc_taxi.init_raw.yml       # DDL de RAW (idempotente)
│       └── nyc_taxi.dbt_build.yml      # dbt deps + dbt build
├── snowflake/setup.sql         # warehouse, DB, rol, usuario de servicio, esquemas
├── scripts/generate_keys.sh    # par de llaves RSA para autenticación key-pair
├── dbt/nyc_taxi/               # proyecto dbt
│   ├── models/bronze/          # vistas sobre RAW + metadata
│   ├── models/silver/          # limpieza y estandarización
│   ├── models/gold/            # esquema estrella
│   ├── seeds/                  # zonas TLC, catálogos, feriados
│   ├── macros/                 # generate_schema_name, periods_to_process
│   ├── tests/                  # tests singulares de reconciliación
│   └── analyses/               # consultas de ejemplo sobre GOLD
└── docs/                       # diagramas
```

## Requisitos

- Docker Desktop (con Docker Compose v2)
- Una cuenta de Snowflake con acceso a `ACCOUNTADMIN` (solo para el setup inicial)
- `openssl` (viene instalado en macOS y Linux)

## Cómo levantar y ejecutar

### 1. Generar las llaves del usuario de servicio

Snowflake ya no permite contraseña sola en usuarios de servicio, por eso se usa autenticación **key-pair**.

```bash
./scripts/generate_keys.sh
```

El script imprime dos valores: `RSA_PUBLIC_KEY` y `SNOWFLAKE_PRIVATE_KEY` (el archivo PEM completo codificado en base64, en una línea). Si ya tienes un par de llaves (PKCS8 sin passphrase), puedes reutilizarlo: `base64 -i rsa_key.p8 | tr -d '\n'`. Las llaves quedan en `keys/`, que está en `.gitignore`.

### 2. Preparar Snowflake (una sola vez)

1. Abrir `snowflake/setup.sql` y reemplazar `<RSA_PUBLIC_KEY>` por la llave pública del paso 1.
2. Ejecutar el script completo en una worksheet de Snowsight con rol `ACCOUNTADMIN`.

El script crea:
- el warehouse `NYC_TAXI_WH` (XS, auto-suspend 60 s);
- la base de datos `NYC_TAXI`;
- el rol `NYC_TAXI_ROLE`;
- el usuario `NYC_TAXI_SVC`;
- los esquemas `RAW`, `BRONZE`, `SILVER` y `GOLD`.

### 3. Configurar variables

```bash
cp .env.example .env
```

Completar en `.env`:
- `SNOWFLAKE_ACCOUNT`: identificador de la cuenta con formato `org-cuenta`. Está en Snowsight → Admin → Accounts.
- `SNOWFLAKE_PRIVATE_KEY`: el valor que imprimió el paso 1.

Las demás variables ya tienen los valores que crea `setup.sql`.

### 4. Levantar la infraestructura

```bash
docker compose up -d --build
```

- La primera vez se construye la imagen de Kestra con dbt (unos minutos).
- El servicio `flow-loader` importa automáticamente los 5 flujos de `kestra/flows/`.
- UI de Kestra: <http://localhost:8080>. Usuario y contraseña: `KESTRA_USER` / `KESTRA_PASSWORD` del `.env` (por defecto `admin@kestra.io` / `Admin1234`).

### 5. Ejecutar el pipeline completo

Desde la UI: **Flows → nyc_taxi → pipeline → Execute**.

O por API:

```bash
source .env
curl -u "$KESTRA_USER:$KESTRA_PASSWORD" -X POST \
  http://localhost:8080/api/v1/main/executions/nyc_taxi/pipeline
```

El pipeline hace lo siguiente:
1. **`backfill`**: descarga cada mes y lo carga en `RAW.YELLOW_TRIPDATA` (4 meses en paralelo).
2. **`dbt_build`**: corre `dbt build`, que carga los seeds, materializa BRONZE, SILVER y GOLD y ejecuta los 88 tests.

Otros usos:
- Recargar un solo mes: ejecutar `nyc_taxi.ingest_month` con `period = 2025-03`.
- Reconstruir todo desde cero: ejecutar `pipeline` con `full_refresh = true`.

> **Meses aún no publicados.** TLC publica cada mes con unos 2 meses de rezago. Al 28-09-2026, `yellow_tripdata_2026-08.parquet` todavía responde **403**.
>
> - La ingesta de ese mes falla con `allowFailure`: el backfill termina en **WARNING** y dbt se ejecuta igual con los meses disponibles.
> - Cuando TLC publique el archivo, basta con volver a ejecutar `pipeline`. Solo se procesa el mes nuevo, sin duplicar los anteriores.
> - El flujo tiene un trigger mensual (día 5), deshabilitado por defecto, para automatizar esta recarga.

### (Opcional) Ejecutar dbt desde la máquina local

```bash
cd dbt/nyc_taxi
python -m venv .venv && source .venv/bin/activate
pip install "dbt-core~=1.12.0" "dbt-snowflake~=1.12.0"
set -a && source ../../.env && set +a
export SNOWFLAKE_PRIVATE_KEY="$(echo "$SNOWFLAKE_PRIVATE_KEY" | base64 -d)"   # base64 -> PEM
dbt deps && dbt debug --profiles-dir . && dbt build --profiles-dir .
```

## Capas

### RAW (aterrizaje, lo carga Kestra)

`RAW.YELLOW_TRIPDATA` contiene exactamente las columnas de los Parquet de TLC. Los tipos son laxos (FLOAT/NUMBER) para tolerar el *schema drift* entre meses. Por ejemplo, en 2026 aparece la columna `request_source`, que no existe en 2025.

Además tiene dos columnas de metadata que agrega el `COPY INTO`:
- `_SOURCE_FILE`: el archivo de origen (`METADATA$FILENAME`).
- `_LOADED_AT`: la fecha de carga (`METADATA$START_SCAN_TIME`).

### Bronze

- `brz_yellow_tripdata` (vista): los datos tal cual la fuente (mismos nombres y valores), con la metadata de linaje `_source_file`, `_source_period` (YYYY-MM, derivado del nombre del archivo) y `_loaded_at`.
- `brz_taxi_zones`: catálogo oficial de zonas.
- Seeds de referencia: zonas TLC, vendors, rate codes, payment types y feriados.

### Silver — limpieza y decisiones de calidad

`slv_yellow_trips_staged` (incremental) procesa **todas** las filas de Bronze y les asigna un `rejection_reason`. Sobre ella hay dos vistas:
- `slv_yellow_trips`: solo filas válidas.
- `slv_yellow_trips_rejected`: filas descartadas con su motivo, para auditoría.

Un test verifica que **ninguna fila se pierde**: válidas + rechazadas = filas de Bronze.

Las decisiones se basan en un perfilamiento de enero 2025 y julio 2026 (unos 3,5 M de filas por mes):

| Dimensión de calidad | Problema observado | Decisión | Justificación |
|---|---|---|---|
| **Tipos de datos** | Montos en `double`, conteos que en algunos meses vienen como float, timestamps en microsegundos | `NUMBER(10,2)` para montos y distancia, `INTEGER` para códigos y conteos, `TIMESTAMP_NTZ` | Precisión monetaria exacta y joins por enteros |
| **Nombres inconsistentes** | `VendorID`, `PULocationID`, `RatecodeID`, `Airport_fee` (mayúsculas mezcladas); zonas con `N/A` | snake_case descriptivo (`vendor_id`, `pickup_location_id`, `airport_fee_amount`…); `N/A` → `Unknown` | Un solo estilo en todo el warehouse |
| **Formatos inconsistentes** | `store_and_fwd_flag` como texto `Y`/`N` | Booleano `is_store_and_forward`; `request_source` con `trim` y `upper` | Tipo semántico correcto |
| **Nulos: códigos** | Unos 15–27 % de filas con `RatecodeID`, `passenger_count`, `store_and_fwd_flag` y `congestion_surcharge` nulos (viajes *Flex Fare*, `payment_type = 0`) | `rate_code_id` nulo o fuera de catálogo → 99 *Unknown*; `payment_type` fuera de catálogo → 5 *Unknown*; `vendor_id` fuera de catálogo → 99 *Unknown* | Son viajes reales con cobro: descartarlos sesgaría el ingreso. Un miembro *Unknown* mantiene la integridad referencial |
| **Nulos: recargos** | `congestion_surcharge`, `airport_fee`, `cbd_congestion_fee` nulos | → 0 | Un recargo ausente significa que no se cobró |
| **Nulos: pasajeros** | `passenger_count` nulo o 0 (unos 0,7 % en 0) | Se deja **NULL** (0 → NULL) | Es un dato de negocio: imputarlo inventaría información. Los promedios lo ignoran |
| **Duplicados** | Filas idénticas en todos los atributos | `trip_id` = hash de todos los atributos; se conserva 1 por `trip_id` y el resto se marca `duplicate` | Dos filas idénticas son indistinguibles: es el mismo viaje reportado dos veces |
| **Inválidos: período** | Pickups fuera del mes del archivo (p. ej. fechas de 2008/2009, o del mes anterior) | Rechazo `pickup_outside_file_period` | Evita cruces entre archivos y duplicados entre meses; son errores del taxímetro |
| **Inválidos: duración** | `dropoff <= pickup` (de 2 k a 42 k filas por mes) o viajes de más de 24 h | Rechazo `non_positive_duration` / `duration_over_limit` | Físicamente imposibles o taxímetro que no se cerró |
| **Inválidos: distancia** | Distancia negativa o de más de 500 mi | Rechazo `invalid_distance` / `distance_over_limit` | Fuera del rango operativo de un taxi de NYC. **Distancia 0 se conserva** (unos 2,6–3,6 % de las filas, con cobro real: tarifas negociadas o fallas del GPS) |
| **Inválidos: montos** | `total_amount <= 0` (unos 1,8 % en ene-2025: anulaciones y reversos) y `fare_amount < 0` | Rechazo `non_positive_total_amount` / `negative_fare_amount` | Son contra-asientos contables, no viajes. Se conservan en `rejected` para auditoría |
| **Inválidos: zonas** | LocationID fuera del catálogo TLC | Rechazo `unknown_location` | Sin zona no hay análisis geográfico. Las zonas 264/265 (*Unknown* / *Outside of NYC*) sí son válidas |

Los umbrales (24 h, 500 mi) son variables en `dbt_project.yml`.

Para ver cuántas filas se rechazan por motivo: `dbt compile -s rejection_summary` y ejecutar `target/compiled/.../rejection_summary.sql`.

### Gold — esquema estrella

Ver [`docs/esquema_estrella.md`](docs/esquema_estrella.md).

- **Tabla de hechos `fct_trips`.** Grano: **un viaje válido**. Métricas: pasajeros, distancia, duración, velocidad promedio, cada componente de la tarifa y el total.
- **Dimensiones:**

  | Dimensión | PK | Contenido |
  |---|---|---|
  | `dim_date` | `date_key` | año, trimestre, mes, día, fin de semana, feriados de EE. UU. |
  | `dim_time` | `time_key` | hora, minuto, franja del día, hora pico |
  | `dim_location` | `location_key` | borough, zona, service zone, aeropuerto |
  | `dim_vendor` | `vendor_key` | proveedor TPEP |
  | `dim_rate_code` | `rate_code_key` | tipo de tarifa |
  | `dim_payment_type` | `payment_type_key` | forma de pago |

- **FKs.** `pickup/dropoff_date_key`, `pickup/dropoff_time_key` y `pickup/dropoff_location_key` son *role-playing*. Además: `vendor_key`, `rate_code_key` y `payment_type_key`. Todas las FKs son `not_null` y están validadas con `relationships`.

## Validación (tests dbt)

`dbt build` ejecuta **88 tests**:

- `not_null` en PKs, FKs, métricas clave y metadata de Bronze/RAW.
- `unique` en todas las PKs de las dimensiones, en `trip_id` (Silver y Gold) y en los seeds.
- `relationships`:
  - cada FK de `fct_trips` → su dimensión;
  - los códigos de Silver → sus catálogos.
- `accepted_values` en `rejection_reason`.
- `dbt_utils.expression_is_true`: duración > 0, total > 0, dropoff ≥ pickup, montos no negativos.
- Tests singulares:
  - `assert_raw_rows_accounted_in_silver`: no se pierden filas entre Bronze y Silver.
  - `assert_fct_trips_reconciles_with_silver`: Silver y Gold tienen el mismo conteo y el mismo ingreso por período.

## Re-ejecución sin duplicados

| Capa | Mecanismo |
|---|---|
| RAW | Por archivo: `DELETE WHERE _source_file = …` + `COPY INTO … FORCE = TRUE` en una transacción. Re-ingestar un mes lo reemplaza completo |
| Silver / Gold | Incremental `delete+insert` con `unique_key = _source_period`. La macro `periods_to_process` elige solo los meses cuyo `_loaded_at` en el origen es más nuevo que el ya materializado. Cada período se reemplaza completo |
| Dimensiones | Tablas reconstruidas en cada `dbt build` a partir de seeds y generadores deterministas |
| Garantía | Tests `unique` sobre `trip_id` y reconciliaciones entre capas en cada ejecución |

Ejecutar `pipeline` N veces deja exactamente el mismo resultado.

## Verificación rápida en Snowflake

```sql
USE DATABASE NYC_TAXI;

-- Filas por archivo en RAW (una fila por mes, sin duplicados)
SELECT _source_file, COUNT(*), MAX(_loaded_at) FROM RAW.YELLOW_TRIPDATA GROUP BY 1 ORDER BY 1;

-- Viajes válidos vs rechazados por mes
SELECT _source_period, COUNT_IF(rejection_reason IS NULL) AS valid, COUNT_IF(rejection_reason IS NOT NULL) AS rejected
FROM SILVER.SLV_YELLOW_TRIPS_STAGED GROUP BY 1 ORDER BY 1;

-- Análisis: viajes e ingreso por borough de origen y mes
SELECT d.year_month, l.borough, COUNT(*) AS trips, SUM(f.total_amount) AS revenue
FROM GOLD.FCT_TRIPS f
JOIN GOLD.DIM_DATE d     ON f.pickup_date_key = d.date_key
JOIN GOLD.DIM_LOCATION l ON f.pickup_location_key = l.location_key
GROUP BY 1, 2 ORDER BY 1, 3 DESC;
```

Hay más consultas de ejemplo en `dbt/nyc_taxi/analyses/`.

## Apagar

```bash
docker compose down        # conserva el historial de Kestra
docker compose down -v     # borra también los volúmenes
```

Los datos en Snowflake no se tocan. El warehouse se suspende solo a los 60 s.
