-- =====================================================================
-- Setup inicial de Snowflake para el laboratorio NYC Yellow Taxi.
-- Ejecutar UNA vez en Snowsight con un usuario que tenga ACCOUNTADMIN.
-- Es idempotente: se puede volver a correr sin romper nada.
-- =====================================================================

USE ROLE ACCOUNTADMIN;

-- 1. Cómputo -----------------------------------------------------------
CREATE WAREHOUSE IF NOT EXISTS NYC_TAXI_WH
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT = 'Warehouse para ingesta y transformaciones NYC Taxi';

-- 2. Rol de la tubería -------------------------------------------------
CREATE ROLE IF NOT EXISTS NYC_TAXI_ROLE;
GRANT ROLE NYC_TAXI_ROLE TO ROLE SYSADMIN;
GRANT USAGE, OPERATE ON WAREHOUSE NYC_TAXI_WH TO ROLE NYC_TAXI_ROLE;

-- 3. Base de datos (propiedad del rol de la tubería) ----------------------
CREATE DATABASE IF NOT EXISTS NYC_TAXI;
GRANT OWNERSHIP ON DATABASE NYC_TAXI TO ROLE NYC_TAXI_ROLE COPY CURRENT GRANTS;

-- 4. Usuario de servicio con autenticación key-pair ------------------------
-- Reemplazar <RSA_PUBLIC_KEY> por la salida de scripts/generate_keys.sh
CREATE USER IF NOT EXISTS NYC_TAXI_SVC
    TYPE = SERVICE
    DEFAULT_ROLE = NYC_TAXI_ROLE
    DEFAULT_WAREHOUSE = NYC_TAXI_WH
    DEFAULT_NAMESPACE = NYC_TAXI.RAW
    COMMENT = 'Usuario de servicio para Kestra y dbt';
ALTER USER NYC_TAXI_SVC SET RSA_PUBLIC_KEY = '<RSA_PUBLIC_KEY>';

-- 5. Esquemas de la arquitectura medallion ------------------------------
USE ROLE NYC_TAXI_ROLE;
USE WAREHOUSE NYC_TAXI_WH;
USE DATABASE NYC_TAXI;

CREATE SCHEMA IF NOT EXISTS RAW    COMMENT = 'Aterrizaje: archivos TLC tal cual + metadata de carga';
CREATE SCHEMA IF NOT EXISTS BRONZE COMMENT = 'dbt: vistas cercanas a la fuente + seeds de referencia';
CREATE SCHEMA IF NOT EXISTS SILVER COMMENT = 'dbt: datos limpios y estandarizados';
CREATE SCHEMA IF NOT EXISTS GOLD   COMMENT = 'dbt: esquema estrella para análisis';

-- Los objetos de RAW (file format, stage, tabla) también los crea el flujo
-- nyc_taxi.backfill con IF NOT EXISTS, así la tubería funciona "desde cero".
