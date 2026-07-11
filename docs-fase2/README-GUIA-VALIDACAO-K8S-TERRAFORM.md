# Guia de Validação — Kubernetes & Terraform

Guia passo a passo para rodar e validar os Blocos E (Kubernetes) e F (Terraform) do **oficina-backend**.

---

## Índice

1. [Visão Geral do Fluxo](#1-visão-geral-do-fluxo)
2. [Pré-requisitos](#2-pré-requisitos)
3. [Opção A — Validação Local com Minikube/Kind](#3-opção-a--validação-local-com-minikubekind)
4. [Opção B — Validação na AWS com Terraform](#4-opção-b--validação-na-aws-com-terraform)
5. [Comandos de Validação Kubernetes](#5-comandos-de-validação-kubernetes)
6. [Testes Funcionais da Aplicação no Cluster](#6-testes-funcionais-da-aplicação-no-cluster)
7. [Troubleshooting](#7-troubleshooting)
8. [Limpeza de Recursos](#8-limpeza-de-recursos)

---

## 1. Visão Geral do Fluxo

```
┌──────────────────────────────────────────────────────────────────┐
│                     FLUXO DE VALIDAÇÃO                           │
│                                                                  │
│  ┌─────────┐    ┌──────────┐    ┌──────────┐    ┌────────────┐  │
│  │ Build   │───→│ Push     │───→│ Deploy   │───→│ Validar    │  │
│  │ Docker  │    │ Registry │    │ K8s      │    │ Endpoints  │  │
│  │ Image   │    │ (local)  │    │ Manifests│    │ & Probes   │  │
│  └─────────┘    └──────────┘    └──────────┘    └────────────┘  │
│                                                                  │
│  Opção A: Minikube/Kind (local, custo zero)                      │
│  Opção B: AWS EKS via Terraform (cloud, ~$180/mês)               │
└──────────────────────────────────────────────────────────────────┘
```

---

## 2. Pré-requisitos

### Ferramentas Necessárias

| Ferramenta | Versão | Para quê | Instalação |
|---|---|---|---|
| **Docker** | >= 24.x | Build da imagem | [docs.docker.com](https://docs.docker.com/get-docker/) |
| **kubectl** | >= 1.29 | Gerenciar cluster K8s | [kubernetes.io](https://kubernetes.io/docs/tasks/tools/) |
| **Minikube** *(Opção A)* | >= 1.32 | Cluster K8s local | [minikube.sigs.k8s.io](https://minikube.sigs.k8s.io/docs/start/) |
| **Terraform** *(Opção B)* | >= 1.5.0 | Provisionar AWS | [terraform.io](https://developer.hashicorp.com/terraform/downloads) |
| **AWS CLI** *(Opção B)* | >= 2.x | Credenciais AWS | [aws.amazon.com/cli](https://aws.amazon.com/cli/) |

### Verificar instalações

```bash
docker --version
kubectl version --client
minikube version        # se Opção A
terraform --version     # se Opção B
aws --version           # se Opção B
```

---

## 3. Opção A — Validação Local com Minikube/Kind

Esta é a forma mais rápida e sem custo para validar os manifests Kubernetes.

### Passo 1 — Iniciar o cluster local

```bash
# Minikube (recomendado — já inclui LoadBalancer via tunnel)
minikube start --cpus=2 --memory=4096 --driver=docker

# Ou Kind (alternativa leve)
# kind create cluster --name oficina
```

### Passo 2 — Build da imagem Docker

```bash
# Navegar para a raiz do projeto
cd fiap-tech-challenge-oficina-mecanica-fase2

# Build da imagem (usando o Dockerfile multi-stage)
docker build -t oficina-backend:latest .
```

> **Tempo estimado**: 3-5 min (primeira vez, com download das dependências Maven)

### Passo 3 — Carregar a imagem no cluster

```bash
# Minikube — carregar imagem local no cluster
minikube image load oficina-backend:latest

# Kind (se estiver usando Kind)
# kind load docker-image oficina-backend:latest --name oficina
```

> **Por que isso é necessário?** O cluster Kubernetes roda dentro de um container Docker próprio e não tem acesso direto às imagens locais da máquina host. Este comando copia a imagem para dentro do cluster.

### Passo 4 — Aplicar os manifests Kubernetes

```bash
# Aplicar todos os manifests de uma vez
kubectl apply -f k8s/
```

**Saída esperada:**
```
namespace/oficina created
configmap/oficina-config created
secret/oficina-secrets created
persistentvolumeclaim/oficina-db-pvc created
deployment.apps/oficina-db created
service/oficina-db created
deployment.apps/oficina-app created
service/oficina-app created
horizontalpodautoscaler.autoscaling/oficina-app-hpa created
```

### Passo 5 — Aguardar os pods ficarem prontos

```bash
# Acompanhar o status dos pods em tempo real
kubectl get pods -n oficina -w
```

**Saída esperada (aguardar até STATUS = Running e READY = 1/1):**
```
NAME                           READY   STATUS    RESTARTS   AGE
oficina-db-xxxxxxxxxx-xxxxx    1/1     Running   0          60s
oficina-app-xxxxxxxxxx-xxxxx   1/1     Running   0          90s
oficina-app-xxxxxxxxxx-xxxxx   1/1     Running   0          90s
```

> **Tempo estimado**: ~90 segundos (o PostgreSQL precisa iniciar antes da aplicação)
>
> **Ctrl+C** para sair do modo watch

### Passo 6 — Acessar a aplicação

```bash
# Minikube — abrir tunnel para o LoadBalancer
minikube tunnel
# (manter este terminal aberto — em outro terminal, continue)

# Descobrir a URL do serviço
minikube service oficina-app -n oficina --url
# Saída: http://192.168.49.2:XXXXX

# Ou via kubectl port-forward (funciona com Minikube e Kind)
kubectl port-forward svc/oficina-app 8080:80 -n oficina
# Acesse: http://localhost:8080
```

### Passo 7 — Validar (ir para a [Seção 5](#5-comandos-de-validação-kubernetes))

---

## 4. Opção B — Validação na AWS com Terraform

### Passo 1 — Configurar credenciais AWS

```bash
aws configure
# AWS Access Key ID: ASIASL5Z532HCNOBJTPO
# AWS Secret Access Key: eJ/yhVTL4+NkY206/4ymbwKMHi8Gjyvm5EdyuYFp
# AWS token: IQoJb3JpZ2luX2VjEPj//////////wEaCXVzLXdlc3QtMiJHMEUCIQDolA1u59LG0j/7DN3+GZRmOKNQYcTq2DSKwzE66xQ5RQIgEmkrmpA436hIngzkrjHWZGCJ+kJALzK6iYq6+8B2aHgqtwIIwP//////////ARABGgwxNjMwNjE4MTY5NzQiDJ5Ourxdamc9KrYw0yqLAuQ1SEv9rZy7QD4ad6PHNShf6GzYSyv4VaifTUQFkwFSGbLvy9dWJaVsx4YXT/UHBs1W/kDAqgbtTdkV/nK8ZWwYqpuovRcL0QsoflIzEoOshHzKGz671QL+YNrQlA8CmHUqLPZ4Sg/rnso6n+nJeY8GSX6cA4dYYNkuteie3x6bn/pkJBCQLUyFVjTSZ4HoYTUBiNn/Pyd/W1sh8hrHjG8E9ZRxaiiH78WLCiz9fA+isaUS3PpBBYQCSgxmGf8ThraEm+TEHgn/CYmoTNNGBStymI2m0Ciw3lNIbspr8H+zqd3bGAsVoOaGgGs0LQUuqn0lnr2k6p+o/dlJnsXR4evQotyqVQlouW7wDTD9+8XSBjqdAbDXinG9jrpfOQhydEEJJVZ4aSQwjB301e06uJKd8jIBbyh3gRRzgTG/wJI1k3hp+7tNZUIkQvthV/wrLZxPhBDps1IykLdtus7mvOtfxSGl3etYS0HJ3uyo7Z5IT0RhBWU9INZNoFa4VbC3dPhE3Z1WKVoB2WnhqmLXysOaldcJuHJUqqtYEZKPb7jWDzfJoyTq1XhNA6v+48+jRfQ=
# Default region: us-east-1
# Default output format: json

# Verificar
aws sts get-caller-identity
```

### Passo 2 — Configurar variáveis do Terraform

```bash
cd fiap-tech-challenge-oficina-mecanica-fase2/infra

# Copiar o arquivo de exemplo
cp terraform.tfvars.example terraform.tfvars

# Editar com seus valores (especialmente db_password)
# Use uma senha forte em produção!
nano terraform.tfvars
```

**Conteúdo do `terraform.tfvars` (editar):**
```hcl
aws_region  = "us-east-1"
environment = "dev"

vpc_cidr           = "10.0.0.0/16"
availability_zones = ["us-east-1a", "us-east-1b"]

cluster_version    = "1.29"
node_instance_type = "t3.medium"
node_desired_count = 2
node_min_count     = 2
node_max_count     = 5

db_instance_class    = "db.t3.micro"
db_name              = "oficina"
db_username          = "oficina"
db_password          = "SUA_SENHA_SEGURA_AQUI"   # <-- ALTERAR!
db_allocated_storage = 20
```

### Passo 3 — Inicializar e aplicar o Terraform

```bash
# Inicializar (baixar providers)
terraform init

# Visualizar o que será criado (sem aplicar)
terraform plan

# Aplicar (provisionar recursos na AWS)
terraform apply
# Digitar "yes" quando solicitado
```

> **Tempo estimado**: 15-25 minutos (EKS demora ~10 min, RDS ~5 min)

**Saída esperada (outputs):**
```
Outputs:

eks_cluster_endpoint = "https://XXXXXXXX.gr7.us-east-1.eks.amazonaws.com"
eks_cluster_name     = "oficina-dev"
eks_kubeconfig_command = "aws eks update-kubeconfig --region us-east-1 --name oficina-dev"
rds_endpoint         = "oficina-dev-db.xxxxxxxx.us-east-1.rds.amazonaws.com:5432"
vpc_id               = "vpc-xxxxxxxxxxxxxxxxx"
```

### Passo 4 — Configurar kubectl para o EKS

```bash
# Usar o comando do output do Terraform
aws eks update-kubeconfig --region us-east-1 --name oficina-dev

# Verificar conexão
kubectl cluster-info
```

### Passo 5 — Build e Push da imagem Docker

```bash
cd fiap-tech-challenge-oficina-mecanica-fase2

# Criar repositório ECR (ou usar Docker Hub/GHCR)
aws ecr create-repository --repository-name oficina-backend --region us-east-1

# Login no ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com

# Build e tag
docker build -t oficina-backend:latest .
docker tag oficina-backend:latest <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/oficina-backend:latest

# Push
docker push <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/oficina-backend:latest
```

### Passo 6 — Ajustar manifests e deployar

```bash
# 1. Atualizar a imagem no app-deployment.yaml
#    Alterar: image: oficina-backend:latest
#    Para:    image: <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/oficina-backend:latest

# 2. Atualizar o DB_URL no configmap.yaml com o endpoint do RDS
#    Alterar: DB_URL: "jdbc:postgresql://oficina-db:5432/oficina"
#    Para:    DB_URL: "jdbc:postgresql://<rds-endpoint>:5432/oficina"

# 3. Atualizar o DB_PASSWORD no secret.yaml
#    echo -n 'SUA_SENHA_SEGURA_AQUI' | base64
#    Substituir o valor de DB_PASSWORD pelo resultado

# 4. Aplicar (sem o postgres-deployment e postgres-service, pois o RDS substitui)
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/secret.yaml
kubectl apply -f k8s/app-deployment.yaml
kubectl apply -f k8s/app-service.yaml
kubectl apply -f k8s/hpa.yaml
```

> **Nota**: Na AWS com RDS, **não** aplique `postgres-deployment.yaml`, `postgres-pvc.yaml` e `postgres-service.yaml` — o RDS substitui o PostgreSQL em pod.

### Passo 7 — Validar (ir para a [Seção 5](#5-comandos-de-validação-kubernetes))

---

## 5. Comandos de Validação Kubernetes

Execute estes comandos para validar que tudo está funcionando:

### 5.1 — Verificar todos os recursos no namespace

```bash
kubectl get all -n oficina
```

**Saída esperada:**
```
NAME                               READY   STATUS    RESTARTS   AGE
pod/oficina-db-xxx-xxx             1/1     Running   0          2m
pod/oficina-app-xxx-xxx            1/1     Running   0          2m
pod/oficina-app-xxx-yyy            1/1     Running   0          2m

NAME                  TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)
service/oficina-db    ClusterIP      10.96.x.x       <none>           5432/TCP
service/oficina-app   LoadBalancer   10.96.x.x       <pending/IP>     80:3xxxx/TCP

NAME                          READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/oficina-db    1/1     1            1           2m
deployment.apps/oficina-app   2/2     2            2           2m

NAME                                              REFERENCE                TARGETS         MINPODS   MAXPODS
horizontalpodautoscaler.autoscaling/oficina-hpa   Deployment/oficina-app   <unknown>/70%   2         5
```

### 5.2 — Verificar health dos pods

```bash
# Verificar se as probes estão passando
kubectl describe pod -l app.kubernetes.io/name=oficina-app -n oficina | grep -A 5 "Conditions:"
```

**Saída esperada:**
```
Conditions:
  Type              Status
  Initialized       True
  Ready             True
  ContainersReady   True
  PodScheduled      True
```

### 5.3 — Verificar logs da aplicação

```bash
# Logs do primeiro pod da aplicação
kubectl logs -l app.kubernetes.io/name=oficina-app -n oficina --tail=50

# Logs do PostgreSQL
kubectl logs -l app.kubernetes.io/name=oficina-db -n oficina --tail=20
```

**Sinais de sucesso nos logs:**
```
Started OficinaApplication in X.XXX seconds
Tomcat started on port 8080
HikariPool-1 - Start completed
Flyway ... Successfully applied 2 migrations
```

### 5.4 — Verificar conectividade entre pods

```bash
# Testar conexão app → banco de dados (de dentro do pod da aplicação)
kubectl exec -it deployment/oficina-app -n oficina -- wget -qO- http://localhost:8080/actuator/health
```

**Saída esperada:**
```json
{"status":"UP","groups":["liveness","readiness"]}
```

### 5.5 — Verificar PersistentVolumeClaim

```bash
kubectl get pvc -n oficina
```

**Saída esperada:**
```
NAME             STATUS   VOLUME        CAPACITY   ACCESS MODES   AGE
oficina-db-pvc   Bound    pvc-xxxxx     5Gi        RWO            2m
```

### 5.6 — Verificar HPA (Autoscaling)

```bash
kubectl get hpa -n oficina
```

**Saída esperada:**
```
NAME              REFERENCE                TARGETS         MINPODS   MAXPODS   REPLICAS   AGE
oficina-app-hpa   Deployment/oficina-app   <cpu>/70%       2         5         2          2m
```

### 5.7 — Verificar ConfigMap e Secret

```bash
# Ver ConfigMap (valores não-sensíveis)
kubectl get configmap oficina-config -n oficina -o yaml

# Ver Secret (nomes das chaves, valores em base64)
kubectl get secret oficina-secrets -n oficina -o yaml
```

---

## 6. Testes Funcionais da Aplicação no Cluster

### 6.1 — Acessar o Swagger UI

```bash
# Se usando port-forward:
kubectl port-forward svc/oficina-app 8080:80 -n oficina &

# Abrir no navegador:
# http://localhost:8080/swagger-ui.html
```

### 6.2 — Testar login (obter JWT)

```bash
# Login com o admin bootstrap
curl -s -X POST http://localhost:8080/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@oficina.local","password":"admin123","ttlMinutos":60}' | jq .

# Salvar o token
export TOKEN=$(curl -s -X POST http://localhost:8080/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@oficina.local","password":"admin123","ttlMinutos":60}' | jq -r '.token')

echo "Token: $TOKEN"
```

**Saída esperada:**
```json
{
  "token": "eyJhbGciOiJIUzI1NiJ9...",
  "type": "Bearer",
  "expiresIn": "60 minutos"
}
```

### 6.3 — Testar cadastro de cliente

```bash
curl -s -X POST http://localhost:8080/api/v1/clientes \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "nome": "João da Silva",
    "documento": "52998224725",
    "email": "joao@email.com",
    "telefone": "(11) 99999-0000"
  }' | jq .
```

**Saída esperada:** HTTP 201 com os dados do cliente criado.

### 6.4 — Testar abertura unificada de OS

```bash
# Primeiro, cadastrar um veículo para o cliente
curl -s -X POST http://localhost:8080/api/v1/veiculos \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "placa": "ABC1D23",
    "marca": "Toyota",
    "modelo": "Corolla",
    "ano": 2024,
    "idCliente": 1
  }' | jq .

# Cadastrar um serviço
curl -s -X POST http://localhost:8080/api/v1/servicos \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "descricao": "Troca de óleo",
    "precoBase": 150.00
  }' | jq .

# Abertura unificada de OS (Bloco B1)
curl -s -X POST http://localhost:8080/api/v1/ordens-servico \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "placa": "ABC1D23",
    "idCliente": 1,
    "itens": [
      {"tipo": "SERVICO", "id": 1, "quantidade": 1}
    ]
  }' | jq .
```

**Saída esperada:** HTTP 201 com a OS criada (status `EM_DIAGNOSTICO`).

### 6.5 — Testar listagem de OS ativas (Bloco B2)

```bash
curl -s http://localhost:8080/api/v1/ordens-servico/ativas \
  -H "Authorization: Bearer $TOKEN" | jq .
```

**Saída esperada:** Lista de OS ordenadas por prioridade (exclui ENTREGUE e CANCELADA).

### 6.6 — Verificar notificação fictícia nos logs (Bloco B3)

```bash
# Verificar se a notificação fictícia aparece nos logs
kubectl logs -l app.kubernetes.io/name=oficina-app -n oficina | grep "NOTIFICAÇÃO FICTÍCIA"
```

**Saída esperada:**
```
[NOTIFICAÇÃO FICTÍCIA] Para: joao@email.com | Status: EM_DIAGNOSTICO | OS: OS-052026-000001
```

### 6.7 — Verificar health check do actuator

```bash
# Liveness (usado pelo Kubernetes para restart automático)
curl -s http://localhost:8080/actuator/health/liveness | jq .

# Readiness (usado pelo Kubernetes para balanceamento de carga)
curl -s http://localhost:8080/actuator/health/readiness | jq .
```

**Saída esperada:**
```json
{"status": "UP"}
```

---

## 7. Troubleshooting

### Pod com STATUS = CrashLoopBackOff

```bash
# Ver os logs do pod que está falhando
kubectl logs <nome-do-pod> -n oficina --previous

# Causas comuns:
# 1. Banco não está pronto → verificar se oficina-db está Running
# 2. Variáveis incorretas → kubectl describe pod <nome> -n oficina
# 3. Imagem não encontrada → verificar se fez image load no Minikube
```

### Pod com STATUS = ImagePullBackOff

```bash
# A imagem não foi encontrada no registry
# Solução para Minikube:
minikube image load oficina-backend:latest

# Solução para Kind:
kind load docker-image oficina-backend:latest --name oficina

# Verificar se imagePullPolicy está como IfNotPresent (não Always)
```

### Pod com STATUS = Pending

```bash
# Verificar eventos do pod
kubectl describe pod <nome-do-pod> -n oficina

# Causas comuns:
# 1. Sem recursos suficientes → aumentar CPU/memória do Minikube
# 2. PVC não vinculado → kubectl get pvc -n oficina
```

### Aplicação não conecta ao banco

```bash
# Verificar se o service do banco existe e resolve
kubectl get svc oficina-db -n oficina

# Testar DNS de dentro do pod
kubectl exec -it deployment/oficina-app -n oficina -- nslookup oficina-db

# Verificar variáveis de ambiente
kubectl exec deployment/oficina-app -n oficina -- env | grep DB_
```

### Terraform apply falhou

```bash
# Ver o estado atual
terraform state list

# Ver recursos com erro
terraform plan

# Forçar recriação de um recurso específico
terraform taint <recurso>
terraform apply
```

---

## 8. Limpeza de Recursos

### Opção A — Cluster Local

```bash
# Remover todos os recursos do namespace
kubectl delete namespace oficina

# Parar o cluster Minikube
minikube stop

# Deletar o cluster completamente
minikube delete
```

### Opção B — AWS (Terraform)

```bash
# Primeiro, remover os recursos Kubernetes
kubectl delete namespace oficina

# Depois, destruir a infraestrutura AWS
cd infra
terraform destroy
# Digitar "yes" para confirmar

# Verificar que não ficou nada na conta AWS
aws eks list-clusters --region us-east-1
aws rds describe-db-instances --region us-east-1
```

> **IMPORTANTE**: Sempre execute `terraform destroy` quando terminar os testes na AWS para evitar custos desnecessários (~$180/mês se mantido ligado).

---

## Checklist de Validação Completo

| # | Validação | Comando | Resultado Esperado |
|---|---|---|---|
| 1 | Namespace criado | `kubectl get ns oficina` | `Active` |
| 2 | Pods running | `kubectl get pods -n oficina` | Todos `1/1 Running` |
| 3 | DB healthcheck | `kubectl exec deploy/oficina-db -n oficina -- pg_isready -U oficina` | `accepting connections` |
| 4 | App healthcheck | `curl localhost:8080/actuator/health` | `{"status":"UP"}` |
| 5 | Swagger UI | Acessar `localhost:8080/swagger-ui.html` | Página carrega com 4 grupos |
| 6 | Login JWT | POST `/auth/login` | Token retornado |
| 7 | CRUD Cliente | POST `/api/v1/clientes` | HTTP 201 |
| 8 | Abertura OS | POST `/api/v1/ordens-servico` | HTTP 201, status=EM_DIAGNOSTICO |
| 9 | OS Ativas | GET `/api/v1/ordens-servico/ativas` | Lista ordenada por prioridade |
| 10 | Notificação | Verificar logs: `grep "NOTIFICAÇÃO"` | Mensagem fictícia no log |
| 11 | HPA ativo | `kubectl get hpa -n oficina` | min=2, max=5 |
| 12 | PVC bound | `kubectl get pvc -n oficina` | `Bound` |
| 13 | Réplicas | `kubectl get deploy oficina-app -n oficina` | `2/2` |
| 14 | Rolling update | `kubectl describe deploy oficina-app -n oficina` | `maxUnavailable: 0` |
