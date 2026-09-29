-- Dimensión tipo de tarifa. PK: rate_code_key.
select
    rate_code_id    as rate_code_key,
    rate_code_name
from {{ ref('rate_codes') }}
