# Guia passo a passo — Subir a infra na AWS via Terraform (da sua máquina)

Este guia mostra, do zero, como provisionar toda a infraestrutura do
**oficina-backend** na AWS usando o Terraform que está em `infra/`.
O layout segue o modelo da Aula 8 (arquivos por recurso) e usa **state remoto
no S3**.

> Resumo do que será criado: VPC + subnets (públicas/privadas) + Internet
> Gateway + NAT Gateway + Route Tables + Cluster EKS + Node Group + IAM Roles +
> Access Entry + RDS PostgreSQL + bucket S3/DynamoDB para o state.

---

## 1. Pré-requisitos (instalar na sua máquina)

| Ferramenta | Versão mínima | Conferir |
|---|---|---|
| Terraform | >= 1.5.0 | `terraform version` |
| AWS CLI | >= 2.x | `aws --version` |
| kubectl | >= 1.29 | `kubectl version --client` |

Links de instalação:
- Terraform: https://developer.hashicorp.com/terraform/downloads
- AWS CLI: https://aws.amazon.com/cli/
- kubectl: https://kubernetes.io/docs/tasks/tools/

---

## 2. Configurar as credenciais AWS

### Opção A — Conta AWS normal (IAM user)
```bash
aws configure
# AWS Access Key ID:     <sua key>
# AWS Secret Access Key: <seu secret>
# Default region name:   us-east-1
# Default output format: json
```

### Opção B — AWS Academy (Learner Lab)
Copie as credenciais do botão **"AWS Details" → "AWS CLI"** do lab e cole no
arquivo `~/.aws/credentials` (elas expiram a cada sessão do lab):
```ini
[default]
aws_access_key_id     = ...
aws_secret_access_key = ...
aws_session_token     = ...
```

Confirme quem você é:
```bash
aws sts get-caller-identity
```

---

## 3. Clonar o repositório e entrar na pasta da infra

```bash
git clone https://github.com/tiagomiele/fiap-tech-challenge-oficina-mecanica-fase2.git
cd fiap-tech-challenge-oficina-mecanica-fase2/infra
```

---

## 4. Configurar as variáveis (`terraform.tfvars`)

### Conta AWS normal
```bash
cp terraform.tfvars.example terraform.tfvars
```

### AWS Academy
```bash
cp terraform.tfvars.academy.example terraform.tfvars

# Descobrir o ARN da LabRole e preencher automaticamente:
LAB_ROLE_ARN=$(aws iam get-role --role-name LabRole --query 'Role.Arn' --output text)
echo "LabRole: $LAB_ROLE_ARN"   # NÃO pode vir vazio
sed -i "s#arn:aws:iam::ACCOUNT_ID:role/LabRole#${LAB_ROLE_ARN}#g" terraform.tfvars
```

Em **qualquer** caso, edite o `terraform.tfvars` e ajuste:
- `db_password` → uma senha segura (obrigatório).
- `state_bucket_name` → um nome **globalmente único** (ex.: `oficina-tfstate-tiago-2026`).
- `aws_region` / `availability_zones` → a região que você vai usar.
- (opcional) `access_entry_role_arn` → IAM role/usuário que terá acesso admin ao
  cluster. No Academy, use a própria LabRole para conseguir rodar o `kubectl`.

> ⚠️ Confirme que a `aws_region` aqui é a mesma das credenciais. Trocar de região
> depois de aplicar deixa recursos órfãos (principalmente o NAT Gateway, que
> consome crédito).

---

## 5. Criar o bucket de state (fase 1 — state local)

O `backend.tf` já vem com o bloco S3 **comentado** de propósito: o bucket
precisa existir antes de virar backend. Então primeiro criamos só o bucket/lock
com state local.

```bash
terraform init
terraform apply -target=aws_s3_bucket.tfstate \
                -target=aws_s3_bucket_versioning.tfstate \
                -target=aws_s3_bucket_server_side_encryption_configuration.tfstate \
                -target=aws_s3_bucket_public_access_block.tfstate \
                -target=aws_dynamodb_table.tflock
# digite "yes" para confirmar
```

---

## 6. Migrar o state para o S3 (fase 2 — state remoto)

1. Abra `infra/backend.tf` e **descomente** o bloco `terraform { backend "s3" {...} }`.
2. Ajuste `bucket` (= o `state_bucket_name` que você definiu) e `region`.
3. Migre o state local para o S3:
```bash
terraform init -migrate-state
# responda "yes" quando perguntar se quer copiar o state existente
```

> Se você **não** quiser usar state remoto agora, pode pular os passos 5 e 6 e
> deixar o `backend.tf` comentado — nesse caso o state fica local (`terraform.tfstate`).

---

## 7. Planejar e aplicar a infra completa

```bash
terraform plan -out=tfplan
```
Confira no fim o resumo `Plan: X to add, ...` e a **região** nos outputs.
No AWS Academy, com `lab_role_arn` preenchido, **não** deve aparecer criação de
`aws_iam_role.cluster` / `aws_iam_role.node`.

```bash
terraform apply tfplan
```
> ⏳ Leva ~15–20 min (EKS + RDS são lentos).

---

## 8. Conectar o kubectl ao cluster

```bash
# o comando exato sai no output "eks_kubeconfig_command":
terraform output -raw eks_kubeconfig_command
# algo como:
aws eks update-kubeconfig --region <regiao> --name oficina-dev

kubectl get nodes   # deve listar os worker nodes
```

---

## 9. Fazer deploy da aplicação no cluster

```bash
# aplique o namespace primeiro, depois o restante:
kubectl apply -f ../k8s/namespace.yaml
kubectl apply -f ../k8s/

# acompanhe:
kubectl get pods -n oficina -w
```

Pegue o endpoint do banco para a aplicação:
```bash
terraform output rds_endpoint
terraform output -raw rds_connection_url   # URL JDBC (sensível)
```

Descubra a URL pública do serviço (LoadBalancer):
```bash
kubectl get svc -n oficina
# use o EXTERNAL-IP do service do app + /swagger-ui/index.html
```

---

## 10. Destruir tudo no final (evita gastar crédito)

```bash
cd infra
terraform destroy
# digite "yes"
```

Confirme que ficou limpo:
```bash
aws eks list-clusters --region <regiao>
aws rds describe-db-instances --region <regiao> --query "DBInstances[].DBInstanceIdentifier"
aws elbv2 describe-load-balancers --region <regiao> --query "LoadBalancers[].LoadBalancerName"
```

> O `destroy` remove o que está no state atual. O **bucket de state** e a
> tabela DynamoDB também serão destruídos se estiverem no state — se você quiser
> preservá-los, remova-os do state antes (`terraform state rm ...`) ou aplique o
> `destroy` com `-target` nos demais recursos.

---

## Solução de problemas

| Sintoma | Causa provável | Correção |
|---|---|---|
| `AccessDenied: iam:CreateRole` | `lab_role_arn` vazio no Academy | Preencha `lab_role_arn` com a LabRole (passo 4) |
| `BucketAlreadyExists` | `state_bucket_name` não é único | Escolha outro nome globalmente único |
| `terraform init` falha no backend S3 | Bucket ainda não existe | Faça a fase 1 (passo 5) antes de descomentar o `backend.tf` |
| Recursos órfãos após trocar de região | State não acompanha mudança de região | Apague manualmente NAT/EIP/VPC na região antiga |
| `kubectl` dá `Unauthorized` | Faltou Access Entry para seu principal | Preencha `access_entry_role_arn` e reaplique |
