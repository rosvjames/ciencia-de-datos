-- Dimensión forma de pago. PK: payment_type_key.
select
    payment_type_id     as payment_type_key,
    payment_type_name
from {{ ref('payment_types') }}
