#!/usr/bin/env bash
# Deploy da aplicacao no EKS do AWS Academy usando o RDS (banco gerenciado).
#
# No AWS Academy o Postgres dentro do cluster NAO funciona: o driver EBS CSI
# precisa de IRSA (role via OIDC), que o lab bloqueia, entao o PVC nunca provisiona.
# A arquitetura correta (e a da Fase 2) usa o RDS criado pelo Terraform.
#
# Este script descobre o endpoint do RDS, cria namespace/ConfigMap/Secret/Deployment/
# Service/HPA e NAO aplica os manifests postgres-*.yaml.
#
# Uso:
#   DB_PASSWORD="<sua-senha-do-rds>" ./deploy-aws-academy.sh
# Variaveis opcionais:
#   REGION (default us-west-2), IMAGE (default GHCR latest)
#   DB_INSTANCE_ID (default oficina-dev-db)
#   JWT_SECRET (se vazio, e gerado aleatorio) / ADMIN_PASSWORD (default de DEV)
#   E-mail real (opcional): MAIL_HOST, MAIL_PORT (default 587), MAIL_USERNAME,
#     MAIL_PASSWORD, MAIL_FROM (default nao-responder@oficina.local). Se MAIL_HOST
#     for informado, ativa NOTIFICACAO_TIPO=smtp; senao usa modo 'log' (ficticio).
#   Ex. Mailtrap:
#     DB_PASSWORD=... MAIL_HOST=sandbox.smtp.mailtrap.io MAIL_USERNAME=... \
#       MAIL_PASSWORD=... ./deploy-aws-academy.sh
set -euo pipefail

REGION="${REGION:-us-west-2}"
IMAGE="${IMAGE:-ghcr.io/tiagomiele/fiap-tech-challenge-oficina-mecanica-fase2:latest}"
DB_INSTANCE_ID="${DB_INSTANCE_ID:-oficina-dev-db}"
MAIL_HOST="${MAIL_HOST:-}"
MAIL_PORT="${MAIL_PORT:-587}"
MAIL_USERNAME="${MAIL_USERNAME:-}"
MAIL_PASSWORD="${MAIL_PASSWORD:-}"
MAIL_FROM="${MAIL_FROM:-nao-responder@oficina.local}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "$MAIL_HOST" ]]; then
  NOTIFICACAO_TIPO="log"
  echo "==> Notificacao: modo 'log' (e-mail ficticio). Para e-mail real, defina MAIL_HOST/MAIL_USERNAME/MAIL_PASSWORD."
else
  NOTIFICACAO_TIPO="smtp"
  echo "==> Notificacao: modo 'smtp' via ${MAIL_HOST}:${MAIL_PORT}"
fi

if [[ -z "${DB_PASSWORD:-}" ]]; then
  echo "ERRO: defina DB_PASSWORD com a MESMA senha da variavel db_password do Terraform." >&2
  echo "Ex.: DB_PASSWORD='<sua-senha-do-rds>' ./deploy-aws-academy.sh" >&2
  exit 1
fi

if [[ -z "${JWT_SECRET:-}" ]]; then
  JWT_SECRET="$(openssl rand -base64 32 2>/dev/null || head -c 32 /dev/urandom | base64)"
  echo "AVISO: JWT_SECRET nao informado; gerando um valor aleatorio forte para esta execucao." >&2
fi
if [[ -z "${ADMIN_PASSWORD:-}" ]]; then
  ADMIN_PASSWORD="admin123"
  echo "AVISO: ADMIN_PASSWORD nao informado; usando valor de DESENVOLVIMENTO. Em producao defina ADMIN_PASSWORD." >&2
fi

echo "==> Descobrindo o endpoint do RDS ($DB_INSTANCE_ID)..."
RDS="$(aws rds describe-db-instances --region "$REGION" --db-instance-identifier "$DB_INSTANCE_ID" --query 'DBInstances[0].Endpoint.Address' --output text)"
if [[ -z "$RDS" || "$RDS" == "None" ]]; then
  echo "ERRO: endpoint do RDS vazio. A instancia '$DB_INSTANCE_ID' existe e as credenciais do lab estao validas?" >&2
  exit 1
fi
STATUS="$(aws rds describe-db-instances --region "$REGION" --db-instance-identifier "$DB_INSTANCE_ID" --query 'DBInstances[0].DBInstanceStatus' --output text)"
echo "    RDS: $RDS (status: $STATUS)"

kubectl apply -f "$HERE/namespace.yaml"

cat <<YAML | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: oficina-config
  namespace: oficina
  labels:
    app.kubernetes.io/part-of: oficina-backend
data:
  DB_URL: "jdbc:postgresql://${RDS}:5432/oficina"
  DB_USER: "oficina"
  SERVER_PORT: "8080"
  SPRING_PROFILES_ACTIVE: ""
  ADMIN_EMAIL: "admin@oficina.local"
  NOTIFICACAO_TIPO: "${NOTIFICACAO_TIPO}"
  NOTIFICACAO_REMETENTE: "${MAIL_FROM}"
  MAIL_HOST: "${MAIL_HOST}"
  MAIL_PORT: "${MAIL_PORT}"
YAML

# Secret via 'kubectl create secret --from-literal' (em vez de YAML inline) para que
# o kubectl faca o escaping correto de senhas com aspas, barras ou outros caracteres.
SECRET_ARGS=(generic oficina-secrets --namespace oficina
  --from-literal=DB_PASSWORD="${DB_PASSWORD}"
  --from-literal=JWT_SECRET="${JWT_SECRET}"
  --from-literal=ADMIN_PASSWORD="${ADMIN_PASSWORD}")
if [[ "$NOTIFICACAO_TIPO" == "smtp" ]]; then
  SECRET_ARGS+=(--from-literal=MAIL_USERNAME="${MAIL_USERNAME}")
  SECRET_ARGS+=(--from-literal=MAIL_PASSWORD="${MAIL_PASSWORD}")
fi
kubectl create secret "${SECRET_ARGS[@]}" --dry-run=client -o yaml | kubectl apply -f -

sed "s#image: oficina-backend:latest#image: ${IMAGE}#" "$HERE/app-deployment.yaml" | kubectl apply -f -
kubectl apply -f "$HERE/app-service.yaml"
kubectl apply -f "$HERE/hpa.yaml"

echo
echo "==> Deploy aplicado. Acompanhe:"
echo "    kubectl get pods -n oficina -w"
echo "    kubectl get svc oficina-app -n oficina   # pegue o EXTERNAL-IP (ELB)"
echo "    depois: http://<EXTERNAL-IP>/swagger-ui/index.html"
