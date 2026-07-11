# Oficina Backend — Sistema de Gestão de Oficina Mecânica

[![CI](https://github.com/tiagomiele/fiap-tech-challenge-oficina-mecanica-fase2/actions/workflows/ci.yml/badge.svg)](https://github.com/tiagomiele/fiap-tech-challenge-oficina-mecanica-fase2/actions/workflows/ci.yml)

**Back-end para gestão completa de uma oficina mecânica de médio porte** — Tech Challenge SOAT / FIAP — Java 21 · Spring Boot 3.3 · PostgreSQL 16 · Clean Architecture · DDD

---

## Sumário

- [Sobre o Projeto](#sobre-o-projeto)
- [Objetivos da Fase 2](#objetivos-da-fase-2)
- [Funcionalidades](#funcionalidades)
- [Arquitetura — Clean Architecture (4 Anéis)](#arquitetura--clean-architecture-4-anéis)
- [Arquitetura de Infraestrutura (AWS)](#arquitetura-de-infraestrutura-aws)
- [Fluxo de Deploy (CI/CD)](#fluxo-de-deploy-cicd)
- [Diagramas de Arquitetura](#diagramas-de-arquitetura)
- [Tecnologias](#tecnologias)
- [Pré-requisitos](#pré-requisitos)
- [Execução Local (Docker Compose)](#execução-local-docker-compose)
- [Deploy em Kubernetes](#deploy-em-kubernetes)
- [Provisionamento da Infraestrutura (Terraform)](#provisionamento-da-infraestrutura-terraform)
- [Variáveis de Ambiente](#variáveis-de-ambiente)
- [Documentação e Collection das APIs](#documentação-e-collection-das-apis)
- [Endpoints Principais](#endpoints-principais)
- [Fluxo da Ordem de Serviço](#fluxo-da-ordem-de-serviço)
- [Estrutura do Projeto](#estrutura-do-projeto)
- [Testes e Cobertura](#testes-e-cobertura)
- [Validação de Arquitetura (ArchUnit)](#validação-de-arquitetura-archunit)
- [Vídeo Demonstrativo](#vídeo-demonstrativo)

---

## Sobre o Projeto

Sistema que permite uma oficina mecânica controlar o **ciclo de vida completo de uma Ordem de Serviço (OS)**: desde o recebimento do veículo até o pagamento e entrega, passando por diagnóstico, orçamento, aprovação do cliente e execução do reparo.

O projeto aplica **Domain-Driven Design (DDD)** com padrões táticos (agregados, value objects, entidades ricas) e está estruturado em **Clean Architecture** com 4 anéis isolados (domain → usecase → adapter → infrastructure).

### O que o sistema oferece

- Cadastro e gestão de **clientes** e **veículos**
- Catálogo de **serviços** e **peças** com controle de preços
- Controle de **estoque** de peças com rastreabilidade de movimentações
- Registro de **notas fiscais de fornecedor** com entrada automática no estoque
- Ciclo completo de **Ordens de Serviço** com múltiplos orçamentos
- **Conta corrente** da oficina (contas a pagar e contas a receber)
- **Relatórios** de tempo médio de execução por OS
- **Consulta pública** de status da OS pelo cliente (sem autenticação)
- **Notificação** ao cliente nas transições de status (log por default; e-mail real via SMTP configurável)

---

## Objetivos da Fase 2

A Fase 2 evolui a aplicação da Fase 1 para garantir **qualidade, resiliência e escalabilidade**, incorporando práticas modernas de infraestrutura e automação:

| Objetivo | Como foi atendido |
|---|---|
| **Reduzir riscos operacionais com infraestrutura escalável** | Cluster Kubernetes (EKS) com múltiplas réplicas + HPA (auto-scaling 2–5 pods por CPU e memória) |
| **Automatizar o provisionamento e o deploy** | Terraform (IaC) para provisionar VPC, EKS e RDS + pipeline CI/CD (GitHub Actions) |
| **Melhorar qualidade e organização do código** | Refatoração para Clean Architecture (4 anéis), Clean Code e 106 testes automatizados |
| **Suportar grandes volumes em horários de pico** | Escalabilidade dinâmica via HPA + rolling updates sem downtime |

---

## Funcionalidades

### Gestão de Clientes e Veículos
- Cadastro com validação de **CPF/CNPJ** (dígitos verificadores)
- Suporte a **placa antiga** (ABC1234) e **Mercosul** (ABC1D23)
- Vínculo veículo ↔ cliente com PK composta (placa + idCliente)

### Ordens de Serviço
- **Abertura unificada** — uma única chamada POST cria a OS já com os itens (serviços e/ou peças) no corpo da requisição
- **Abertura Recebida** — endpoint dedicado que cria a OS apenas com dados básicos (sem serviços, peças ou orçamento), em status `RECEBIDA` (comportamento da Fase 1)
- **Relatório de OS por status** (Perfil Administrativo) com ordenação por prioridade `EM_EXECUCAO(1) > AGUARDANDO_APROVACAO(2) > EM_DIAGNOSTICO(3) > RECEBIDA(4)` e, dentro de cada grupo, pela data de inclusão (da mais antiga para a mais recente) — exclui automaticamente PAGA, ENTREGUE e CANCELADA
- **Cancelamento em diagnóstico** (Perfil Técnico) — cancela todos os orçamentos vinculados, devolve as peças ao estoque e move a OS para `CANCELADA`
- **Alteração genérica de status** (contingência do Perfil Administrativo) com validação das regras por status de destino
- Suporte a **múltiplos orçamentos** (rejeitar e refazer)
- Transições de status controladas com **máquina de estados**
- **Notificação** ao cliente em cada transição de status (`log` com marcador `[NOTIFICAÇÃO FICTÍCIA]` por default, ou **e-mail real via SMTP** com `NOTIFICACAO_TIPO=smtp`)

### Estoque e Suprimentos
- Saldo de estoque **nunca negativo** (invariante no domínio)
- 4 tipos de movimentação: `ENTRADA_NF`, `ESTORNO_NF`, `CONSUMO_ORCAMENTO`, `DEVOLUCAO_ORCAMENTO`
- Peças consumidas ao serem adicionadas ao orçamento; devolvidas se o orçamento for rejeitado
- Registro de NF de fornecedor com crédito automático no estoque e geração de conta a pagar

### Financeiro
- **Contas a pagar**: geradas na emissão de NF de fornecedor
- **Contas a receber**: geradas na confirmação de pagamento da OS
- Suporte a estorno de lançamentos

### Relatórios
- Tempo médio de execução por OS (baseado nos timestamps `inicio_execucao` e `fim_execucao`)
- OS por status (grupos na ordem `EM_EXECUCAO > AGUARDANDO_APROVACAO > EM_DIAGNOSTICO > RECEBIDA`; dentro de cada grupo, por data de inclusão crescente)

### Segurança
- Autenticação via **JWT** (HMAC-SHA256) com validade configurável (1–1440 min)
- Senhas hash com **BCrypt(12)**
- 2 perfis de acesso: `FUNCIONARIO_DA_OFICINA` (admin) e `TECNICO_DA_OFICINA`
- Hierarquia: funcionário herda todas as permissões do técnico
- Consulta pública do status da OS **sem autenticação**

---

## Arquitetura — Clean Architecture (4 Anéis)

O projeto segue os princípios da **Clean Architecture (Uncle Bob)**, organizado em **4 anéis** com dependências sempre apontando para dentro:

```
┌─────────────────────────────────────────────────────────────────┐
│  4. INFRASTRUCTURE  (anel externo — composition root)           │
│  SecurityConfig, AdminBootstrap, OpenApiConfig                  │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  3. ADAPTER  (interface adapters)                         │  │
│  │  Controllers, DTOs, JPA Repos, JWT, Notification          │  │
│  │                                                           │  │
│  │  ┌─────────────────────────────────────────────────────┐  │  │
│  │  │  2. USECASE  (application business rules)           │  │  │
│  │  │  Services, Gateway interfaces                       │  │  │
│  │  │                                                     │  │  │
│  │  │  ┌───────────────────────────────────────────────┐  │  │  │
│  │  │  │  1. DOMAIN  (enterprise business rules)       │  │  │  │
│  │  │  │  Entities, Value Objects, Enums, Exceptions   │  │  │  │
│  │  │  └───────────────────────────────────────────────┘  │  │  │
│  │  └─────────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

**Regras de dependência:**
- `domain` → **puro**: sem Spring, sem JPA, sem Servlet — apenas Java puro
- `usecase` → depende de `domain`; define interfaces `*Gateway` e `*Repository`
- `adapter` → implementa gateways e repositórios; depende de `usecase` e `domain`
- `infrastructure` → composition root (configurações Spring); depende de `adapter`, `usecase` e `domain`

Essas regras são **validadas automaticamente** por 5 testes ArchUnit a cada build.

![Clean Architecture — 4 anéis](docs-fase1/arquitetura/oficina-clean-arch-aneis.png)

> Para um exemplo detalhado com teste de mesa percorrendo todos os 4 anéis, veja [`README-TESTE-DE-MESA.md`](docs-fase2/README-TESTE-DE-MESA.md).

---

## Arquitetura de Infraestrutura (AWS)

A infraestrutura é provisionada via Terraform (`/infra`) na AWS, com a aplicação orquestrada por Kubernetes (EKS) e banco gerenciado (RDS):

```
┌──────────────────────────── AWS Cloud ─────────────────────────────┐
│                                                                     │
│  ┌──────────────────── VPC 10.0.0.0/16 ───────────────────────┐    │
│  │                                                            │    │
│  │   Subnets Públicas (2 AZs)        Subnets Privadas (2 AZs) │    │
│  │   ┌──────────────────┐            ┌──────────────────────┐ │    │
│  │   │ Internet Gateway │            │  EKS Cluster (1.31)  │ │    │
│  │   │ NAT Gateway      │──────────▶ │  Node Group          │ │    │
│  │   │ LoadBalancer(ELB)│            │  (t3.medium, 2–5)    │ │    │
│  │   └──────────────────┘            │  ┌────────────────┐  │ │    │
│  │            ▲                      │  │ oficina-app x2+ │  │ │    │
│  │            │                      │  │ (HPA 2–5 pods)  │  │ │    │
│  │   tráfego externo                 │  └───────┬────────┘  │ │    │
│  │   (porta 80)                      │          │           │ │    │
│  │                                   │  ┌───────▼────────┐  │ │    │
│  │                                   │  │ RDS PostgreSQL │  │ │    │
│  │                                   │  │ 16 (db.t3.micro)│ │ │    │
│  │                                   │  └────────────────┘  │ │    │
│  │                                   └──────────────────────┘ │    │
│  └────────────────────────────────────────────────────────────┘    │
│                                                                     │
│   ECR (registry da imagem Docker)   ◀── push da imagem pelo CI/CD   │
└─────────────────────────────────────────────────────────────────────┘
```

**Componentes provisionados** (detalhes em [`infra/README-infra.md`](./infra/README-infra.md)):

| Componente | Serviço AWS | Função |
|---|---|---|
| Rede | VPC + subnets + IGW + NAT | Isolamento e conectividade |
| Orquestração | EKS (Kubernetes 1.31) | Executa os containers da aplicação |
| Compute | EC2 (t3.medium, 2–5 nodes) | Worker nodes do cluster |
| Banco de dados | RDS PostgreSQL 16 | Persistência gerenciada |
| Registry | GHCR (ghcr.io) | Armazena a imagem Docker |

![Arquitetura de Infraestrutura (AWS)](docs-fase1/arquitetura/oficina-infra-aws.png)

---

## Fluxo de Deploy (CI/CD)

O deploy é automatizado por **GitHub Actions** em dois workflows que se complementam (detalhes em [`README-BLOCO-G-CICD.md`](docs-fase2/README-BLOCO-G-CICD.md)):

```
  Desenvolvedor faz push / merge na main
               │
               ▼
  ┌─────────────────────────────┐
  │  CI  (.github/workflows/ci.yml)
  │  1. Build (mvnw verify)     │
  │  2. 106 testes + JaCoCo     │
  │  3. SBOM (CycloneDX)        │
  │  4. Trivy (vulnerabilidades)│
  └──────────────┬──────────────┘
                 │ sucesso
                 ▼
  ┌─────────────────────────────┐
  │  CD  (.github/workflows/cd.yml)
  │  G1. Docker build + push GHCR│
  │  G2/G3. kubectl apply -f k8s/│
  │     • namespace             │
  │     • configmap + secret    │
  │     • postgres (banco)      │
  │     • app + service         │
  │     • hpa (auto-scaling)    │
  │     • rollout status        │
  └──────────────┬──────────────┘
                 ▼
     Cluster Kubernetes atualizado
        (app + banco no ar)
```

![Fluxo de Deploy (CI/CD)](docs-fase1/arquitetura/oficina-fluxo-cicd.png)

---

## Diagramas de Arquitetura

Coleção completa de diagramas (fontes versionados em [`docs/arquitetura/`](docs-fase1/arquitetura)):

| Diagrama | Descrição |
|---|---|
| [C4 — Nível 1 (Contexto)](docs-fase1/arquitetura/oficina-c4-nivel1.png) | Usuários e sistemas externos que interagem com a aplicação |
| [C4 — Nível 2 (Contêiner)](docs-fase1/arquitetura/oficina-c4-nivel2.png) | Contêineres executáveis (API, banco, K8s Service/HPA, ConfigMap/Secret) |
| [C4 — Nível 3 (Componente)](docs-fase1/arquitetura/oficina-c4-nivel3.png) | Componentes internos da API nos 4 anéis da Clean Architecture |
| [Arquitetura lúdica (detalhada)](docs-fase1/arquitetura/oficina-arquitetura-ludica.png) | Visão fim a fim: GitHub → CI/CD → GHCR → AWS/EKS → RDS/Mailtrap + Terraform |
| [Arquitetura (alto nível)](docs-fase1/arquitetura/oficina-arquitetura-altonivel.png) | Mesma visão colapsada em blocos macro para leitura rápida |
| [Clean Architecture (4 anéis)](docs-fase1/arquitetura/oficina-clean-arch-aneis.png) | Anéis concêntricos com a regra de dependência (DIP) |
| [Infraestrutura AWS](docs-fase1/arquitetura/oficina-infra-aws.png) | VPC, subnets, IGW/NAT, ELB, EKS, HPA, RDS provisionados por Terraform |
| [Fluxo de Deploy (CI/CD)](docs-fase1/arquitetura/oficina-fluxo-cicd.png) | Pipeline CI → CD → `kubectl apply` no cluster |
| [Processo (value stream)](docs-fase1/arquitetura/oficina-processo.png) | Fluxo de entrega em 6 fases com gates de qualidade |

---

## Tecnologias

| Camada | Tecnologia |
|---|---|
| Linguagem | Java 21 (LTS) |
| Build | Maven 3.9 (via wrapper `./mvnw`) |
| Framework | Spring Boot 3.3.4 |
| Persistência | Spring Data JPA + Hibernate 6 + Flyway |
| Banco de Dados | PostgreSQL 16 |
| Segurança | Spring Security 6 + JWT (jjwt) + BCrypt |
| Validação | Jakarta Validation |
| Documentação API | springdoc-openapi (Swagger UI) |
| Observabilidade | Spring Actuator + Logback |
| Containerização | Docker (multi-stage) + Docker Compose |
| Testes | JUnit 5, AssertJ, Mockito, ArchUnit, Testcontainers, RestAssured |
| Cobertura | JaCoCo (gate ≥ 80% em `domain.model`) |
| Segurança (CI) | SBOM CycloneDX + Trivy |

---

## Pré-requisitos

- **Docker Desktop** (Windows/Mac) ou **Docker Engine + Docker Compose v2** (Linux)
- **Git**
- (Opcional) **Java 21** — apenas se quiser rodar testes localmente fora do container

---

## Execução Local (Docker Compose)

### 1. Clonar o repositório

```bash
git clone https://github.com/tiagomiele/fiap-tech-challenge-oficina-mecanica-fase2.git
cd fiap-tech-challenge-oficina-mecanica-fase2
```

### 2. Subir a aplicação com Docker Compose

```bash
docker compose up --build -d
```

Esse comando sobe 3 serviços:
- **db** — PostgreSQL 16 (porta 5432)
- **app** — Aplicação Spring Boot (porta 8080)
- **adminer** — Interface web para o banco de dados (porta 8081)

### 3. Aguardar a aplicação ficar pronta

```bash
# Verificar se a aplicação está saudável
curl http://localhost:8080/actuator/health
```

Resposta esperada:
```json
{"status":"UP"}
```

### 4. Fazer login e obter o token JWT

A aplicação cria automaticamente um usuário administrador no primeiro boot:

| Campo | Valor padrão |
|---|---|
| E-mail | `admin@oficina.local` |
| Senha | `admin123` |

```bash
curl -s -X POST http://localhost:8080/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@oficina.local","senha":"admin123"}'
```

Resposta:
```json
{
  "accessToken": "eyJhbGciOiJIUzI1NiI...",
  "expiresIn": 900,
  "papel": "FUNCIONARIO_DA_OFICINA",
  "email": "admin@oficina.local"
}
```

### 5. Usar o token nas requisições autenticadas

```bash
# Salvar o token em uma variável
TOKEN=$(curl -s -X POST http://localhost:8080/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@oficina.local","senha":"admin123"}' | jq -r '.accessToken')

# Exemplo: listar clientes
curl -H "Authorization: Bearer $TOKEN" http://localhost:8080/clientes
```

### 6. Acessar o Swagger UI

Abra no navegador: **http://localhost:8080/swagger-ui.html**

O Swagger UI lista todos os endpoints organizados em 4 grupos:
1. **01 — Autenticação** — login e cadastro de usuários
2. **02 — Administrativo** — clientes, veículos, serviços, peças, estoque, NF, OS, financeiro, relatórios
3. **03 — Técnico** — diagnóstico, orçamento, execução, finalização
4. **04 — Cliente** — aprovação, rejeição, pagamento, consulta pública

### 7. Acessar o Adminer (interface do banco)

Abra no navegador: **http://localhost:8081**

| Campo | Valor |
|---|---|
| Sistema | PostgreSQL |
| Servidor | db |
| Usuário | oficina |
| Senha | oficina |
| Base de dados | oficina |

### 8. Parar a aplicação

```bash
docker compose down
```

Para remover também os volumes (dados do banco):
```bash
docker compose down -v
```

---

## Deploy em Kubernetes

Os manifestos estão em [`/k8s`](./k8s) e cobrem Deployments, Services, ConfigMap, Secret e HPA. Há duas formas de validar: **local (Minikube)** ou **cloud (EKS)**.

### Opção A — Local com Minikube

```bash
# 1. Remover somente o perfil local incompleto
minikube delete -p minikube

# 2. Recriar usando Kubernetes 1.31, versão alinhada ao projeto
minikube start --driver=docker --cpus=2 --memory=4096 --kubernetes-version=v1.31.0

# 3. Confirmar que o item 1 terminou corretamente
minikube status
kubectl get nodes

#Resultado esperado:
#host: Running
#kubelet: Running
#apiserver: Running
#kubeconfig: Configured

# 2. Apontar o Docker para o Minikube e buildar a imagem
#    A imagem TEM que ser buildada ANTES do apply (o manifesto usa imagePullPolicy: IfNotPresent; sem a imagem local, os pods ficam em ErrImagePull).
& minikube -p minikube docker-env --shell powershell | Invoke-Expression
docker build -t oficina-backend:latest .

#Para comprovar que a imagem foi criada dentro do Docker do Minikube:
minikube image ls | Select-String "oficina-backend"

#Deve aparecer docker.io/library/oficina-backend:latest (ou nome equivalente

# 3. Aplicar os manifestos — o namespace PRIMEIRO
#    (kubectl aplica a pasta em ordem alfabética; sem isso, app/configmap/hpa
#     falham com 'namespaces "oficina" not found')
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/

# 4. Aguardar os pods ficarem prontos (Ctrl+C quando ambos estiverem 1/1 Running)
kubectl get pods -n oficina -w

# 5. Acessar a aplicação
kubectl port-forward svc/oficina-app 8080:80 -n oficina
# Abra: http://localhost:8080/swagger-ui/index.html
```

> 🪟 **No Windows (PowerShell)** o `eval $(minikube docker-env)` não funciona. Use:
> ```powershell
> & minikube -p minikube docker-env --shell powershell | Invoke-Expression
> ```
> Esse comando vale **só para a janela atual** do PowerShell — se abrir outra, rode de novo antes de `docker build`.
>
> 💡 Após um `kubectl rollout restart deployment/oficina-app -n oficina`, o `port-forward` antigo cai (estava preso ao pod removido). Rode o `kubectl port-forward ...` de novo apontando para os pods novos.

### Opção B — Cloud (AWS EKS)

Na nuvem há detalhes que **não** existem no local (imagem vinda de registry público, banco no RDS com endpoint que muda a cada apply, LoadBalancer/ELB, custo). Por isso, **siga o runbook dedicado e já testado**: [`RUNBOOK-EXECUCAO-AWS-ACADEMY.md`](docs-fase2/RUNBOOK-EXECUCAO-AWS-ACADEMY.md).

Resumo do que muda em relação ao local:

| Ponto | Local (Minikube) | Cloud (AWS EKS) |
|---|---|---|
| Imagem | buildada localmente (`oficina-backend:latest`) | registry **público** (`ghcr.io/tiagomiele/...`) |
| Banco | PostgreSQL no cluster (`postgres-*.yaml`) | **RDS** — `DB_URL` derivado do `terraform output` (muda a cada apply) |
| Acesso | `port-forward` → `localhost:8080` | **LoadBalancer/ELB** com URL pública |
| Custo | grátis | consome crédito → rode `terraform destroy` no fim |

### Recursos aplicados

| Recurso | Arquivo | Função |
|---|---|---|
| Namespace | `namespace.yaml` | Isola os recursos no namespace `oficina` |
| ConfigMap | `configmap.yaml` | Variáveis não-sensíveis (URL do banco, porta) |
| Secret | `secret.yaml` | Variáveis sensíveis (senha do banco, JWT) |
| Deployment (banco) | `postgres-deployment.yaml` + `postgres-pvc.yaml` | PostgreSQL com volume persistente |
| Service (banco) | `postgres-service.yaml` | ClusterIP 5432 (acesso interno) |
| Deployment (app) | `app-deployment.yaml` | 2 réplicas, probes, rolling update |
| Service (app) | `app-service.yaml` | LoadBalancer 80 → 8080 (acesso externo) |
| HPA | `hpa.yaml` | Auto-scaling 2–5 pods quando CPU > 70% |

> Guia detalhado de validação (passo a passo + troubleshooting): [`README-GUIA-VALIDACAO-K8S-TERRAFORM.md`](docs-fase2/README-GUIA-VALIDACAO-K8S-TERRAFORM.md).

---

## Provisionamento da Infraestrutura (Terraform)

Os scripts estão em [`/infra`](./infra) e provisionam toda a infraestrutura AWS (VPC, EKS e RDS).

### Pré-requisitos

- **AWS CLI** configurado (`aws configure`)
- **Terraform** >= 1.5
- **kubectl** >= 1.30

### Passo a passo

```bash
cd infra

# 1. Copiar e ajustar as variáveis (região, senha do banco, etc.)
cp terraform.tfvars.example terraform.tfvars

# 2. Inicializar o Terraform (baixa o provider AWS)
terraform init

# 3. Visualizar o que será criado
terraform plan

# 4. Provisionar a infraestrutura (~15-20 min)
terraform apply

# 5. Configurar o kubectl para o cluster criado (usar o output do apply)
aws eks update-kubeconfig --region us-east-1 --name oficina-dev
```

Ao final, o Terraform exibe os outputs (nome/endpoint do cluster, endpoint do RDS e o comando do kubectl). A documentação completa dos recursos, custos estimados e instruções de destruição (`terraform destroy`) está em [`infra/README-infra.md`](./infra/README-infra.md).

> Passo a passo completo de execução em todos os ambientes (local, Minikube e AWS): [`README-GUIA-EXECUCAO-COMPLETO.md`](./README-GUIA-EXECUCAO-COMPLETO.md).

---

## Variáveis de Ambiente

| Variável | Default | Descrição |
|---|---|---|
| `DB_URL` | `jdbc:postgresql://localhost:5432/oficina` | URL JDBC do banco |
| `DB_USER` | `oficina` | Usuário do banco |
| `DB_PASSWORD` | `oficina` | Senha do banco |
| `JWT_SECRET` | placeholder (≥ 32 bytes) | Chave HMAC para tokens JWT. **Trocar em produção.** Gere com: `openssl rand -base64 48` |
| `ADMIN_EMAIL` | `admin@oficina.local` | E-mail do admin criado no bootstrap |
| `ADMIN_PASSWORD` | `admin123` | Senha do admin criado no bootstrap |
| `SERVER_PORT` | `8080` | Porta HTTP da aplicação |
| `SPRING_PROFILES_ACTIVE` | (vazio) | Perfil Spring ativo |
| `NOTIFICACAO_TIPO` | `log` | `log` registra a notificação no log; `smtp` envia e-mail real |
| `NOTIFICACAO_REMETENTE` | `nao-responder@oficina.local` | Remetente dos e-mails (modo `smtp`) |
| `MAIL_HOST` | (vazio) | Host SMTP (ex.: `sandbox.smtp.mailtrap.io`) — usado quando `NOTIFICACAO_TIPO=smtp` |
| `MAIL_PORT` | `587` | Porta SMTP |
| `MAIL_USERNAME` | (vazio) | Usuário SMTP |
| `MAIL_PASSWORD` | (vazio) | Senha SMTP |

### Notificação de status por e-mail

A cada transição de status da OS o cliente é notificado. Há dois modos, selecionados por `NOTIFICACAO_TIPO`:

- **`log`** (default): registra a notificação no log com o marcador `[NOTIFICAÇÃO FICTÍCIA]`. Não exige servidor de e-mail — ideal para desenvolvimento, testes e CI.
- **`smtp`**: envia um e-mail real via SMTP usando as variáveis `MAIL_*`. Para a demonstração recomenda-se o **[Mailtrap](https://mailtrap.io)** (caixa *sandbox* gratuita):

  ```bash
  NOTIFICACAO_TIPO=smtp
  MAIL_HOST=sandbox.smtp.mailtrap.io
  MAIL_PORT=587
  MAIL_USERNAME=<usuario-do-inbox>
  MAIL_PASSWORD=<senha-do-inbox>
  ```

  Veja [`.env.example`](./.env.example) para o conjunto completo de variáveis.

---

## Documentação e Collection das APIs

Após subir a aplicação, a documentação interativa (que serve como **collection completa das APIs**) está disponível em:

- **Swagger UI**: http://localhost:8080/swagger-ui.html
- **OpenAPI JSON (spec/collection)**: http://localhost:8080/v3/api-docs

Cada endpoint possui:
- Descrição detalhada via `@Operation`
- Schemas de request/response com exemplos preenchidos
- Códigos de resposta documentados (200, 201, 204, 400, 401, 403, 404, 409, 422)

### Exportar a collection

A especificação OpenAPI pode ser exportada e importada em qualquer cliente (Postman, Insomnia, etc.):

```bash
# Baixar a spec OpenAPI (JSON) com a aplicação rodando
curl http://localhost:8080/v3/api-docs -o oficina-openapi.json
```

- **Postman**: `Import` → selecione o arquivo `oficina-openapi.json` (o Postman gera a collection automaticamente).
- **Insomnia**: `Import/Export` → `Import Data` → `From File`.

---

## Endpoints Principais

| Área | Rota | Método | Auth |
|---|---|---|---|
| **Login** | `/auth/login` | POST | Pública |
| **Cadastro de usuário** | `/usuarios` | POST | JWT (admin) |
| **Clientes** | `/clientes` | POST/GET/PUT | JWT (admin) |
| **Veículos** | `/veiculos` | POST/GET/PUT | JWT (admin) |
| **Serviços** | `/servicos` | POST/GET/PUT | JWT (admin) |
| **Peças** | `/pecas` | POST/GET/PUT | JWT (admin) |
| **Estoque** | `/estoque` | GET | JWT (admin) |
| **NF Fornecedor** | `/notas-fiscais-fornecedor` | POST/GET | JWT (admin) |
| **Abrir OS (unificada)** | `/ordens-servico` | POST | JWT (admin) |
| **Abrir OS (Recebida)** | `/ordens-servico/recebida` | POST | JWT (admin) |
| **Alterar status da OS (contingência)** | `/ordens-servico/{numeroOs}/status` | PATCH | JWT (admin) |
| **Contas a pagar** | `/contas-a-pagar` | GET | JWT (admin) |
| **Contas a receber** | `/contas-a-receber` | GET | JWT (admin) |
| **Relatório tempo médio por OS** | `/relatorios/tempo-medio-por-os` | GET | JWT (admin) |
| **Relatório OS por status** | `/relatorios/os-por-status` | GET | JWT (admin) |
| **Adicionar serviço à OS** | `/ordens-servico/{numeroOs}/servicos` | POST | JWT (técnico) |
| **Adicionar peça à OS** | `/ordens-servico/{numeroOs}/pecas` | POST | JWT (técnico) |
| **Enviar para aprovação** | `/ordens-servico/{numeroOs}/enviar-para-aprovacao` | POST | JWT (técnico) |
| **Concluir reparo** | `/ordens-servico/{numeroOs}/concluir-reparo` | POST | JWT (técnico) |
| **Entregar veículo** | `/ordens-servico/{numeroOs}/entregar` | POST | JWT (técnico) |
| **Cancelar OS em diagnóstico** | `/ordens-servico/{numeroOs}/cancelar-diagnostico` | POST | JWT (técnico) |
| **Aprovar orçamento** | `/ordens-servico/{numeroOs}/aprovar` | POST | Pública |
| **Rejeitar e refazer** | `/ordens-servico/{numeroOs}/rejeitar-refazer` | POST | Pública |
| **Rejeitar e cancelar** | `/ordens-servico/{numeroOs}/rejeitar-cancelar` | POST | Pública |
| **Confirmar pagamento** | `/ordens-servico/{numeroOs}/confirmar-pagamento` | POST | Pública |
| **Consultar status (público)** | `/consulta/ordens-servico/{numeroOs}/status` | GET | Pública |

---

## Fluxo da Ordem de Serviço

A OS segue uma máquina de estados controlada pelo domínio:

```
RECEBIDA → EM_DIAGNOSTICO → AGUARDANDO_APROVACAO → EM_EXECUCAO → AGUARDANDO_PAGAMENTO → PAGA → ENTREGUE
                  ↑                    |
                  |         rejeitarRefazer()
                  └────────────────────┘
                                       |
                            rejeitarCancelar() → CANCELADA → ENTREGUE
```

**Passo a passo:**

1. **Abrir OS** (`POST /api/v1/ordens-servico`) → cria com status `RECEBIDA` ou `EM_DIAGNOSTICO` (se já houver itens)
2. **Adicionar serviços/peças** → transita para `EM_DIAGNOSTICO`. Peças consomem estoque imediatamente
3. **Enviar para aprovação** → `AGUARDANDO_APROVACAO`
4. **Cliente aprova** → `EM_EXECUCAO` (grava `inicio_execucao`)
5. **Concluir reparo** → `AGUARDANDO_PAGAMENTO` (grava `fim_execucao`)
6. **Confirmar pagamento** → `PAGA` (gera lançamento financeiro)
7. **Entregar veículo** → `ENTREGUE`

**Caminhos alternativos:**
- **Rejeitar e refazer**: cancela o orçamento atual, abre um novo, estorna peças → volta para `EM_DIAGNOSTICO`
- **Rejeitar e cancelar**: cancela o orçamento, estorna peças → `CANCELADA` → pode entregar o veículo

---

## Estrutura do Projeto

```
src/main/java/br/com/oficina/
├── OficinaApplication.java                # Ponto de entrada
│
├── domain/                                # ANEL 1 — DOMAIN (regras de negócio puras)
│   ├── model/                             #   Entidades e Value Objects
│   │   ├── OrdemServico.java              #     Raiz de agregado (ciclo da OS)
│   │   ├── ItemOrcamento.java             #     Itens do orçamento
│   │   ├── Cliente.java, Veiculo.java     #     Entidades de cadastro
│   │   ├── Dinheiro.java                  #     Value Object monetário
│   │   ├── Documento.java                 #     Value Object CPF/CNPJ
│   │   ├── NumeroOS.java                  #     Value Object formato OS-MMAAAA-NNNNNN
│   │   ├── Placa.java                     #     Value Object placa veicular
│   │   └── ...                            #     EstoquePeca, Servico, Peca, etc.
│   ├── enums/                             #   StatusOrdemServico, TipoItem, etc.
│   └── exception/                         #   BusinessException
│
├── usecase/                               # ANEL 2 — USECASE (regras de aplicação)
│   ├── OrdemServicoServiceImpl.java       #   Lógica de aplicação da OS
│   ├── ClienteServiceImpl.java            #   CRUD de clientes
│   ├── EstoqueServiceImpl.java            #   Gestão de estoque
│   ├── ...                                #   Demais services
│   └── gateway/                           #   Interfaces (contratos de saída)
│       ├── ClienteRepository.java         #     Contrato para persistência de clientes
│       ├── NotificacaoGateway.java        #     Contrato para notificações
│       ├── TokenGateway.java              #     Contrato para geração de tokens
│       ├── RelatorioGateway.java          #     Contrato para relatórios
│       └── ...                            #     Demais gateways
│
├── adapter/                               # ANEL 3 — ADAPTER (interface adapters)
│   ├── controller/                        #   Controllers REST (4 controllers)
│   │   ├── AuthController.java
│   │   ├── AdministrativoOficinaController.java
│   │   ├── TecnicoOficinaController.java
│   │   └── ClienteOficinaController.java
│   ├── persistence/                       #   JPA Entities + Repository implementations
│   │   ├── *JpaEntity.java                #     Entidades JPA (mapeamento ORM)
│   │   ├── Jpa*Repository.java            #     Implementações dos gateways
│   │   └── SpringData*Repository.java     #     Interfaces Spring Data
│   ├── security/                          #   JWT (geração e validação de tokens)
│   │   ├── JwtTokenService.java           #     Implementa TokenGateway
│   │   ├── JwtAuthenticationFilter.java   #     Filtro de autenticação
│   │   └── JwtProperties.java             #     Propriedades JWT
│   ├── notification/                      #   LogNotificacaoGateway (notificação fictícia)
│   ├── dto/                               #   Objetos de transporte (response)
│   └── exception/                         #   GlobalExceptionHandler, ApiError, RequestIdFilter
│
├── infrastructure/                        # ANEL 4 — INFRASTRUCTURE (composition root)
│   └── config/                            #   Configurações Spring
│       ├── SecurityConfig.java            #     Spring Security + filtros
│       ├── AdminBootstrap.java            #     Criação do admin no primeiro boot
│       ├── OpenApiConfig.java             #     Swagger/OpenAPI
│       └── SwaggerOrderConfig.java        #     Ordenação customizada no Swagger UI
│
src/test/java/br/com/oficina/
├── architecture/                          # Testes ArchUnit (5 regras)
├── domain/model/                          # Testes unitários do domínio
├── domain/exception/                      # Testes de exceções
└── integration/                           # Testes E2E (Testcontainers + RestAssured)
```

---

## Testes e Cobertura

### Executar todos os testes

```bash
./mvnw clean verify
```

**106 testes** no total:
- **97 testes unitários** do domínio (sem Spring context)
- **5 testes ArchUnit** (validação de regras arquiteturais — 4 anéis)
- **4 testes de integração E2E** (Testcontainers + RestAssured com PostgreSQL 16)

### Cobertura (JaCoCo)

O build exige **≥ 80% de cobertura** (line + branch) no pacote `br.com.oficina.domain.model`. O build **falha** se a cobertura cair abaixo desse limiar.

Relatório HTML: `target/site/jacoco/index.html`

### Classes de domínio cobertas

| Classe | Tipo | Classe de Teste |
|---|---|---|
| `Dinheiro` | Value Object | `DinheiroTest` |
| `Documento` | Value Object (CPF/CNPJ) | `DocumentoTest` |
| `Placa` | Value Object | `PlacaTest` |
| `NumeroOS` | Value Object | `NumeroOSTest` |
| `Cliente` | Entidade | `ClienteTest` |
| `Veiculo` | Entidade | `VeiculoTest` |
| `Servico` | Entidade | `ServicoTest` |
| `Peca` | Entidade | `PecaTest` |
| `EstoquePeca` | Entidade | `EstoquePecaTest` |
| `MovimentacaoEstoque` | Entidade | `MovimentacaoEstoqueTest` |
| `LancamentoFinanceiro` | Entidade | `LancamentoFinanceiroTest` |
| `NotaFiscalFornecedor` | Agregado | `NotaFiscalFornecedorTest` |
| `ItemOrcamento` | Entidade | `ItemOrcamentoTest` |
| `Orcamento` | Agregado | `OrcamentoTest` |
| `OrdemServico` | Agregado raiz | `OrdemServicoTest` |

---

## Validação de Arquitetura (ArchUnit)

5 testes automatizados garantem a integridade da Clean Architecture (4 anéis):

1. **4 camadas respeitam dependências** — `infrastructure` → `adapter` → `usecase` → `domain` (nunca o contrário)
2. **Domínio puro (sem Spring)** — `domain` não pode depender de Spring, JPA ou Servlet
3. **Domínio puro (sem JPA)** — `domain` não importa `jakarta.persistence` nem `org.hibernate`
4. **Usecase isolado** — `usecase` não pode depender de `adapter` nem `infrastructure`
5. **Adapter isolado** — `adapter` não pode depender de `infrastructure`

Localização: `src/test/java/br/com/oficina/architecture/ArchitectureTest.java`

---

## Vídeo Demonstrativo

Vídeo (até 15 min) demonstrando deploy da aplicação, execução do CI/CD, consumo das APIs e escalabilidade automática (HPA):

- **Link**: _a publicar (YouTube/Vimeo)_

---

## CI/CD (GitHub Actions)

Dois workflows complementares automatizam build, testes e deploy:

**CI (`ci.yml`)** — a cada push/PR:
1. **Build, Test & Coverage** — `./mvnw -B verify` (compilação + testes + JaCoCo)
2. **SBOM** — gera relatório CycloneDX de dependências
3. **Trivy Scan** — análise de vulnerabilidades (HIGH/CRITICAL)

**CD (`cd.yml`)** — no push à `main` (ou disparo manual):
1. **Docker build & push** — constrói a imagem e publica no GHCR
2. **Deploy no Kubernetes** — `kubectl apply -f k8s/` (banco + app + manifestos) e aguarda o rollout (requer o secret `KUBECONFIG`)

> Detalhes, diagrama e guia de validação do CD em [`README-BLOCO-G-CICD.md`](docs-fase2/README-BLOCO-G-CICD.md).

---

## Banco de Dados

- **PostgreSQL 16** com **Flyway** para migrações versionadas
- Hibernate em modo `validate` (Flyway é o dono do schema)
- 2 migrações: `V1__schema_inicial.sql` (schema completo) + `V2__ordens_servico_inicio_fim_execucao.sql` (timestamps de execução)

---

## Documentação Adicional

Toda a documentação do projeto está organizada em [`/docs`](docs-fase1/README-DOCS.md), incluindo:

| Tema | Local |
|---|---|
| DDD (Storytelling, Event Storming, Linguagem Ubíqua) | `docs/` |
| Decisões arquiteturais (ADR) | `docs/` |
| Segurança (Dependency-Track, Trivy) | `docs/04-security/` |
| Apresentação Tech Challenge | `README-apresentacao-tech-challenge-fase1.md` |
