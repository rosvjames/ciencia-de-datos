#!/usr/bin/env bash
# Genera un par de llaves RSA para autenticación key-pair del usuario de servicio de Snowflake.
# - keys/rsa_key.p8   : llave privada PKCS8 sin passphrase (NO se sube al repo)
# - keys/rsa_key.pub  : llave pública
# Imprime el valor para RSA_PUBLIC_KEY (snowflake/setup.sql) y para SNOWFLAKE_PRIVATE_KEY (.env).
# Si ya tienes un par de llaves, no hace falta correr esto: solo codifica tu .p8 con
#   base64 -i rsa_key.p8 | tr -d '\n'
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p keys
openssl genrsa 2048 2>/dev/null | openssl pkcs8 -topk8 -inform PEM -out keys/rsa_key.p8 -nocrypt
openssl pkey -in keys/rsa_key.p8 -pubout -out keys/rsa_key.pub

echo "== RSA_PUBLIC_KEY (pegar en snowflake/setup.sql) =="
grep -v -- '-----' keys/rsa_key.pub | tr -d '\n'; echo
echo
echo "== SNOWFLAKE_PRIVATE_KEY (pegar en .env: PEM completo en base64) =="
base64 < keys/rsa_key.p8 | tr -d '\n'; echo
