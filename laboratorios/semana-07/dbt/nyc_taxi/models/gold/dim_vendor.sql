-- Dimensión proveedor TPEP. PK: vendor_key.
select
    vendor_id   as vendor_key,
    vendor_name
from {{ ref('vendors') }}
