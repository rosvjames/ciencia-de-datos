#!/bin/sh
# Importa (upsert) todos los flujos de /flows en Kestra vía API.
# Se ejecuta automáticamente con el servicio flow-loader de docker compose.
set -eu
API="${KESTRA_URL:-http://kestra:8080}/api/v1/main/flows/import"
for f in /flows/*.yml; do
  code=$(curl -s -o /tmp/resp -w '%{http_code}' -u "$KESTRA_USER:$KESTRA_PASSWORD" \
         -X POST -F "fileUpload=@$f" "$API")
  echo "$(basename "$f") -> HTTP $code $(cat /tmp/resp)"
  [ "$code" = "200" ] || exit 1
done
