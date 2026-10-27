#!/usr/bin/env bash
set -euo pipefail

# FreshBox SpA - Inicialización de RDS MySQL desde un Pod efímero en EKS.
# Ejecutar desde cualquier directorio dentro de un contexto kubectl configurado.

REGION="${AWS_REGION:-us-east-1}"
DB_INSTANCE_IDENTIFIER="${DB_INSTANCE_IDENTIFIER:-freshbox-db}"
DB_NAME="freshbox"
DB_USER="alumno"
DB_PASS="alumno123"
NAMESPACE="${NAMESPACE:-freshbox}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
INIT_SQL="${INIT_SQL:-$REPOSITORY_ROOT/init.sql}"

command -v aws >/dev/null 2>&1 || {
  echo "Error: AWS CLI no está instalado o no está disponible en PATH." >&2
  exit 1
}
command -v kubectl >/dev/null 2>&1 || {
  echo "Error: kubectl no está instalado o no está disponible en PATH." >&2
  exit 1
}
[[ -f "$INIT_SQL" ]] || {
  echo "Error: no se encontró el archivo SQL: $INIT_SQL" >&2
  exit 1
}

DB_ENDPOINT="$(aws rds describe-db-instances \
  --db-instance-identifier "$DB_INSTANCE_IDENTIFIER" \
  --region "$REGION" \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)"

if [[ -z "$DB_ENDPOINT" || "$DB_ENDPOINT" == "None" ]]; then
  echo "Error: no se pudo obtener el endpoint de $DB_INSTANCE_IDENTIFIER." >&2
  exit 1
fi

kubectl get namespace "$NAMESPACE" >/dev/null
echo "Inicializando $DB_NAME en RDS endpoint $DB_ENDPOINT..."

kubectl run rds-client \
  --rm -i \
  --restart=Never \
  --image=mysql:8.0 \
  --namespace="$NAMESPACE" \
  --env="MYSQL_PWD=$DB_PASS" \
  -- mysql -h "$DB_ENDPOINT" -u "$DB_USER" "$DB_NAME" < "$INIT_SQL"

echo "Validando registros de productos..."

kubectl run rds-client \
  --rm -i \
  --restart=Never \
  --image=mysql:8.0 \
  --namespace="$NAMESPACE" \
  --env="MYSQL_PWD=$DB_PASS" \
  -- mysql -h "$DB_ENDPOINT" -u "$DB_USER" "$DB_NAME" \
  -e "SELECT id, nombre, precio, stock FROM productos;"

echo "Inicialización y validación completadas."
