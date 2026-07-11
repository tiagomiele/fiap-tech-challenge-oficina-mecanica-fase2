# Documentação Geral — Oficina Backend

Sistema de **gestão de oficina mecânica**: gerencia clientes, veículos, ordens de serviço (OS), orçamentos, estoque de peças, serviços, notas fiscais de fornecedor, financeiro e notificações ao cliente. É uma **API REST** em **Java 21 / Spring Boot 3**, construída em **Clean Architecture** (conformidade verificada por testes), containerizada com Docker, orquestrada em Kubernetes (EKS), provisionada por Terraform e entregue por uma esteira CI/CD no GitHub Actions.

Este documento explica **tudo o que a aplicação contém e tudo o que ela faz**.

---

## Índice

1. [Visão geral e propósito](#1-visão-geral-e-propósito)
2. [O que a aplicação faz (funcionalidades)](#2-o-que-a-aplicação-faz-funcionalidades)
3. [Perfis de acesso e segurança](#3-perfis-de-acesso-e-segurança)
4. [Arquitetura de software (Clean Architecture)](#4-arquitetura-de-software-clean-architecture)
5. [Modelo de domínio](#5-modelo-de-domínio)
6. [Ciclo de vida da Ordem de Serviço](#6-ciclo-de-vida-da-ordem-de-serviço)
7. [Camada de aplicação (use cases e ports)](#7-camada-de-aplicação-use-cases-e-ports)
8. [Adapters (entrada e saída)](#8-adapters-entrada-e-saída)
9. [Persistência e banco de dados](#9-persistência-e-banco-de-dados)
10. [Notificações (e-mail)](#10-notificações-e-mail)
11. [Mapa de endpoints da API](#11-mapa-de-endpoints-da-api)
12. [Tecnologias e dependências](#12-tecnologias-e-dependências)
13. [Qualidade: testes e verificações](#13-qualidade-testes-e-verificações)
14. [Infraestrutura: Docker, Kubernetes, Terraform, CI/CD](#14-infraestrutura-docker-kubernetes-terraform-cicd)
15. [Como executar](#15-como-executar)
16. [Estrutura de diretórios](#16-estrutura-de-diretórios)

---

## 1. Visão geral e propósito

A oficina precisava evoluir de um sistema inicial para uma plataforma **escalável, resiliente e automatizada**. Esta aplicação é o **backend** que expõe as regras de negócio da oficina como uma API REST segura, pronta para rodar em cluster Kubernetes com autoescala e para ser provisionada/entregue de forma automatizada.

**Stack central:** Java 21, Spring Boot 3 (Web, Security, Data JPA, Mail, Actuator, Validation), PostgreSQL 16, Flyway, JWT, SpringDoc/OpenAPI (Swagger).

---

## 2. O que a aplicação faz (funcionalidades)

### Gestão de Clientes e Veículos
- Cadastro/edição/consulta/remoção de **clientes** (com documento CPF/CNPJ validado).
- Cadastro/consulta/remoção de **veículos** vinculados a um cliente (identificados por placa).

### Ordens de Serviço (OS) — núcleo do sistema
- **Abertura de OS** com dados de cliente, veículo, descrição do problema e, opcionalmente, itens (serviços e peças) já no orçamento.
- **Orçamento**: composição de itens (serviços + peças), recálculo de valor total.
- **Ciclo de vida completo** por máquina de estados (ver seção 6): diagnóstico, envio para aprovação, aprovação/rejeição pelo cliente, execução, pagamento e entrega.
- **Consulta pública de status** da OS (sem login).
- **Listagem de OS ativas** ordenada por prioridade de status e antiguidade, excluindo logicamente as concluídas.
- **Cancelamento** de OS em diagnóstico (devolve peças ao estoque e cancela orçamentos).
- **Alteração de status** de contingência (perfil administrativo), respeitando as regras de transição.

### Estoque e Suprimentos
- Cadastro de **peças** e **serviços** (catálogo).
- Controle de **estoque de peças** com **movimentações** (entrada/saída) rastreáveis.
- **Notas fiscais de fornecedor** (entrada de peças e geração de contas a pagar).

### Financeiro
- **Lançamentos financeiros**: contas a pagar (NF de fornecedor) e contas a receber (pagamento de OS).
- Consultas de **contas a pagar** e **contas a receber**.

### Relatórios
- **Tempo médio por OS**.
- **OS por status** (listagem ativa ordenada — atende o requisito de listagem do edital).

### Segurança e Notificações
- **Autenticação por JWT** e autorização por perfil (roles).
- **Notificação por e-mail** ao cliente a cada mudança de status da OS (modo log ou SMTP).

---

## 3. Perfis de acesso e segurança

A autorização é baseada em **JWT + roles** (`@PreAuthorize`). Existem dois papéis internos (`domain/enums/Papel.java`) e um acesso público:

| Perfil | Role | Acesso | Exemplos |
|--------|------|--------|----------|
| **Cliente (público)** | — (sem token) | Rotas públicas | Consultar status, aprovar/rejeitar orçamento, confirmar pagamento |
| **Administrativo (Perfil 02)** | `FUNCIONARIO_DA_OFICINA` | Rotas privadas | Clientes, veículos, serviços, peças, estoque, NF, financeiro, relatórios, abrir/alterar OS |
| **Técnico (Perfil 03)** | `TECNICO_DA_OFICINA` | Rotas privadas | Diagnóstico, orçamento, execução, entrega, cancelamento em diagnóstico |

**Componentes de segurança** (`adapter/security/`):
- `JwtTokenService` — emissão/validação de token (implementa a port `TokenGateway`).
- `JwtAuthenticationFilter` — extrai e valida o `Authorization: Bearer <token>` a cada request.
- `JwtProperties` — configuração da chave/expiração.
- `SecurityConfig` (`infrastructure/config/`) — define rotas públicas/privadas, filtro JWT e regras de autorização.
- `AdminBootstrap` — cria o usuário administrador inicial no startup (`ADMIN_EMAIL`/`ADMIN_PASSWORD`).

> Nota de transporte: hoje a API trafega em **HTTP** (porta 8080; Service K8s em 80). O JWT autentica/autoriza mas não criptografa o transporte — TLS/HTTPS seria uma evolução (terminação no ELB/Ingress com ACM).

---

## 4. Arquitetura de software (Clean Architecture)

O código segue **Clean Architecture** com 4 camadas concêntricas; a **regra de dependência aponta sempre para dentro** e é **verificada automaticamente por ArchUnit** (`src/test/java/br/com/oficina/architecture/ArchitectureTest.java`) — se alguém violar, o build falha.

```
br.com.oficina
├── domain           # 1. Regras de negócio corporativas (núcleo puro, sem framework)
│   ├── model        #    Entidades e Value Objects
│   ├── enums        #    Enums de domínio
│   └── exception    #    Exceções de domínio
├── usecase          # 2. Regras de aplicação (orquestração)
│   └── gateway      #    Ports (interfaces) — repositórios, notificação, token, relatório
├── adapter          # 3. Interface adapters (traduzem o mundo externo ↔ núcleo)
│   ├── controller   #    Controllers REST (entrada)
│   ├── dto          #    DTOs de request/response
│   ├── persistence  #    Implementações JPA das ports (saída)
│   ├── security     #    JWT (saída/segurança)
│   ├── notification #    Gateways de notificação (saída)
│   └── exception    #    GlobalExceptionHandler (@ControllerAdvice)
└── infrastructure   # 4. Composition root / configuração (Spring)
    └── config       #    SecurityConfig, OpenApiConfig, AdminBootstrap, SwaggerOrderConfig
```

**Princípios aplicados:**
- **SOLID** — responsabilidade única (domínio guarda regra, service orquestra, controller expõe HTTP); aberto/fechado e inversão de dependência via **ports** (`usecase/gateway`) implementadas por adapters (JPA, SMTP, JWT).
- **Clean Code** — nomes ricos em pt-BR, Value Objects que blindam invariantes, máquina de estados explícita, tratamento de erro centralizado.
- **DIP** — o núcleo (domain/usecase) depende só de interfaces; as implementações concretas ficam no adapter e são injetadas pela infrastructure.

---

## 5. Modelo de domínio

### Entidades e agregados (`domain/model/`)
- **`OrdemServico`** (aggregate root) — coração do sistema; contém a máquina de estados e as regras (`enviarParaAprovacao`, `aprovar`, `concluirReparo`, `confirmarPagamento`, `entregar`, cancelamentos).
- **`Orcamento`** + **`ItemOrcamento`** — orçamento da OS e seus itens (serviços/peças) com valores.
- **`Cliente`**, **`Veiculo`** — cadastros básicos.
- **`Servico`**, **`Peca`** — catálogo.
- **`EstoquePeca`** + **`MovimentacaoEstoque`** — estoque e histórico de movimentações.
- **`NotaFiscalFornecedor`** + **`ItemNotaFiscalFornecedor`** — entrada de peças por NF.
- **`LancamentoFinanceiro`** — contas a pagar/receber.
- **`User`** — usuário administrativo/técnico (autenticação).
- **`RaizDeAgregado`** / **`EventoDominio`** — base para agregados e eventos de domínio.

### Value Objects (blindam invariantes)
- **`Dinheiro`** (valores monetários), **`Placa`** (placa de veículo), **`Documento`** (CPF/CNPJ), **`NumeroOS`** (número da OS no formato `OS-MMAAAA-NNNNNN`).

### Enums de domínio (`domain/enums/`)
- **`StatusOrdemServico`** — estados da OS + **prioridade de listagem** + regra `visivelNaListagem()`.
- **`StatusOrcamentoItem`**, **`TipoItem`**, **`TipoRejeicao`**, **`Papel`** (roles), **`TipoLancamento`**, **`OrigemLancamento`**, **`OrigemMovimentacao`**.

---

## 6. Ciclo de vida da Ordem de Serviço

A OS é uma **máquina de estados** (enum `StatusOrdemServico`). A prioridade de listagem e a visibilidade seguem exatamente o edital:

| Status | Prioridade (listagem) | Visível na listagem ativa? |
|--------|----------------------|----------------------------|
| `EM_EXECUCAO` | 1 (topo) | ✅ |
| `AGUARDANDO_APROVACAO` | 2 | ✅ |
| `EM_DIAGNOSTICO` | 3 | ✅ |
| `RECEBIDA` | 4 | ✅ |
| `AGUARDANDO_PAGAMENTO` | 5 | ✅ |
| `PAGA` | 6 | ❌ (finalizada) |
| `ENTREGUE` | 7 | ❌ (entregue) |
| `CANCELADA` | 8 | ❌ (cancelada) |

**Fluxo típico:**
1. **RECEBIDA** — OS aberta (`POST /ordens-servico` ou `/recebida`).
2. **EM_DIAGNOSTICO** — técnico adiciona serviços/peças ao orçamento.
3. **AGUARDANDO_APROVACAO** — técnico envia para o cliente (`enviar-para-aprovacao`).
4. Cliente decide (rotas públicas):
   - **aprovar** → **EM_EXECUCAO**;
   - **rejeitar-refazer** → volta para **EM_DIAGNOSTICO**;
   - **rejeitar-cancelar** → **CANCELADA** (devolve peças, cancela orçamentos).
5. **EM_EXECUCAO** → técnico `concluir-reparo` → **AGUARDANDO_PAGAMENTO**.
6. Cliente `confirmar-pagamento` → **PAGA** (gera conta a receber).
7. Técnico `entregar` → **ENTREGUE**.

A cada transição, o sistema **notifica o cliente por e-mail** (se houver e-mail cadastrado).

**Listagem ativa** (`OrdemServicoServiceImpl.listarAtivas`): filtra `visivelNaListagem()` e ordena por `prioridadeListagem` (asc) e depois por `criadoEm` (mais antigas primeiro) — atendendo ao requisito do edital.

---

## 7. Camada de aplicação (use cases e ports)

### Services (`usecase/*ServiceImpl.java`) — `@Service @Transactional`
Orquestram regras de aplicação e efeitos colaterais (persistência, estoque, notificação):
`OrdemServicoServiceImpl`, `ClienteServiceImpl`, `VeiculoServiceImpl`, `ServicoServiceImpl`, `PecaServiceImpl`, `EstoqueServiceImpl`, `NotaFiscalFornecedorServiceImpl`, `FinanceiroServiceImpl`, `AuthServiceImpl`, `UserServiceImpl`.

### Ports / Gateways (`usecase/gateway/`) — interfaces (DIP)
- **Repositórios:** `OrdemServicoRepository`, `ClienteRepository`, `VeiculoRepository`, `ServicoRepository`, `PecaRepository`, `EstoqueRepository`, `NotaFiscalFornecedorRepository`, `LancamentoFinanceiroRepository`, `UserRepository`.
- **Serviços externos:** `NotificacaoGateway` (e-mail), `TokenGateway` (JWT), `RelatorioGateway`, `NumeroOSGenerator`.
- **Consultas especializadas:** `OsAtivaPorCliente/Veiculo/Servico/PecaConsulta` (evitam exclusões indevidas de cadastros com OS ativa).

O núcleo depende **apenas dessas interfaces** — nunca de Spring/JPA/SMTP diretamente.

---

## 8. Adapters (entrada e saída)

### Entrada — Controllers REST (`adapter/controller/`)
- **`AuthController`** — login/JWT e criação de usuários administrativos.
- **`ClienteOficinaController`** — rotas **públicas** do cliente (consulta status, aprovar/rejeitar, confirmar pagamento).
- **`AdministrativoOficinaController`** — rotas do **Perfil 02** (o maior controller: clientes, veículos, serviços, peças, NF, estoque, financeiro, relatórios, OS).
- **`TecnicoOficinaController`** — rotas do **Perfil 03** (diagnóstico, orçamento, execução, entrega, listagem, cancelamento).

**DTOs** em `adapter/dto/` (requests/responses) e **tratamento de erros** centralizado em `adapter/exception/GlobalExceptionHandler` (`@ControllerAdvice`).

### Saída — implementações das ports
- **Persistência JPA** (`adapter/persistence/`): para cada port há uma implementação (`Jpa*Repository`) que usa um `SpringData*Repository` e mapeia entre **entidade de domínio** e **entidade JPA** (`*JpaEntity`). O domínio permanece puro (garantido por ArchUnit).
- **Notificação** (`adapter/notification/`): `LogNotificacaoGateway` (default) e `SmtpNotificacaoGateway` (Spring Mail) — implementam `NotificacaoGateway`.
- **Segurança** (`adapter/security/`): `JwtTokenService` implementa `TokenGateway`.

---

## 9. Persistência e banco de dados

- **Banco:** PostgreSQL 16 (RDS em produção; container em dev/local).
- **ORM:** Spring Data JPA / Hibernate.
- **Migrações:** Flyway em `src/main/resources/db/migration/`:
  - `V1__schema_inicial.sql` — schema inicial completo.
  - `V2__ordens_servico_inicio_fim_execucao.sql` — colunas de início/fim de execução da OS.
- **Geração do número da OS:** sequência controlada (`NumeroOSSequencia*`) via `JpaNumeroOSGenerator`.

---

## 10. Notificações (e-mail)

O sistema envia **e-mail ao cliente** a cada mudança de status da OS (fluxo **unidirecional**: sistema → cliente). É configurável por perfil via `NOTIFICACAO_TIPO`:
- **`log`** (default) — apenas registra no log (`LogNotificacaoGateway`), útil em dev.
- **`smtp`** — envia de verdade via Spring Mail (`SmtpNotificacaoGateway`), usando `MAIL_HOST/PORT/USERNAME/PASSWORD` (ex.: Mailtrap sandbox).

> A aprovação/rejeição feita pelo cliente é uma **chamada de API** (não um e-mail); ela apenas dispara mais um e-mail do sistema para o cliente informando o novo status.

---

## 11. Mapa de endpoints da API

Documentação interativa (Swagger/OpenAPI) — serve como **collection** das APIs:
- Swagger UI: `http://localhost:8080/swagger-ui.html`
- OpenAPI JSON: `http://localhost:8080/v3/api-docs` (importável no Postman/Insomnia)

### Autenticação (`AuthController`)
- `POST /auth/login` — login e emissão de JWT.
- `POST /usuarios` — cadastrar usuário administrativo.

### Cliente — público (`ClienteOficinaController`)
- `GET /consulta/ordens-servico/{numeroOs}/status` — consultar status da OS.
- `POST /ordens-servico/{numeroOs}/aprovar` — aprovar orçamento.
- `POST /ordens-servico/{numeroOs}/rejeitar-refazer` — rejeitar e refazer.
- `POST /ordens-servico/{numeroOs}/rejeitar-cancelar` — rejeitar e cancelar.
- `POST /ordens-servico/{numeroOs}/confirmar-pagamento` — confirmar pagamento.

### Técnico — Perfil 03 (`TecnicoOficinaController`, base `/ordens-servico`)
- `GET /ordens-servico` — listar OS ativas; `GET /ordens-servico/{numeroOs}` — detalhe.
- `POST /{numeroOs}/servicos` e `POST /{numeroOs}/pecas` — compor orçamento.
- `POST /{numeroOs}/enviar-para-aprovacao`, `POST /{numeroOs}/concluir-reparo`, `POST /{numeroOs}/entregar`.

### Administrativo — Perfil 02 (`AdministrativoOficinaController`)
CRUD de **clientes, veículos, serviços, peças**, **notas fiscais de fornecedor**, consultas de **estoque**, **relatórios** (`/relatorios/tempo-medio-por-os`, `/relatorios/os-por-status`), **financeiro** (`/contas-a-receber`, `/contas-a-pagar`) e OS:
- `POST /ordens-servico` — **abrir OS** (com cliente, veículo, serviços e peças; retorna o número da OS).
- `POST /ordens-servico/recebida` — abrir OS apenas com dados básicos (status RECEBIDA).
- `PATCH /ordens-servico/{numeroOs}/status` — alterar status (contingência, com regras).

---

## 12. Tecnologias e dependências

| Categoria | Tecnologia |
|-----------|-----------|
| Linguagem/Runtime | Java 21 (Eclipse Temurin) |
| Framework | Spring Boot 3 (Web, Security, Data JPA, Mail, Actuator, Validation) |
| Banco | PostgreSQL 16 |
| Migrações | Flyway |
| Autenticação | JWT (`jjwt`) |
| Documentação | SpringDoc OpenAPI (Swagger UI) |
| Build | Maven (wrapper `./mvnw`) |
| Utilitários | Lombok, Logstash Logback encoder |
| Testes | JUnit 5, RestAssured, Spring Security Test, ArchUnit |
| Cobertura | JaCoCo (gate no build) |
| Qualidade/segurança | Spotless (format), CycloneDX (SBOM), OWASP Dependency-Check, Trivy, SonarQube |
| Container | Docker (multi-stage) |
| Orquestração | Kubernetes / Amazon EKS |
| IaC | Terraform |
| CI/CD | GitHub Actions |

---

## 13. Qualidade: testes e verificações

- **~117 testes** (`@Test`): unitários de domínio + integração E2E (RestAssured cobrindo o fluxo completo da OS) + testes de arquitetura.
- **ArchUnit** (`architecture/ArchitectureTest.java`): garante as dependências da Clean Architecture (domínio puro, sem Spring/JPA; camadas respeitadas).
- **JaCoCo**: relatório de cobertura com **gate** no build (`./mvnw verify` falha se abaixo do mínimo).
- **Spotless**: formatação de código.
- **SBOM (CycloneDX)** e **Trivy/OWASP Dependency-Check**: inventário e varredura de vulnerabilidades no CI.

Comando único que roda tudo: `./mvnw verify`.

---

## 14. Infraestrutura: Docker, Kubernetes, Terraform, CI/CD

### Conteinerização
- **`Dockerfile`** — build multi-stage (JDK para compilar, JRE para rodar), usuário não-root, `EXPOSE 8080`, HEALTHCHECK em `/actuator/health/liveness`.
- **`docker-compose.yml`** — ambiente local: `db` (Postgres 16), `app` (a API) e `adminer` (UI do banco).

### Kubernetes (`/k8s`)
- **Deployments:** `app-deployment.yaml` (2 réplicas, RollingUpdate, probes readiness/liveness/startup) e `postgres-deployment.yaml`.
- **Services:** `app-service.yaml` (LoadBalancer, 80→8080) e `postgres-service.yaml`.
- **ConfigMap/Secret:** `configmap.yaml` (config não sensível) e `secret.yaml` (senha do banco, JWT, admin) — injetados via `envFrom`.
- **HPA:** `hpa.yaml` — autoescala 2–5 pods por **CPU (70%)** e **memória (80%)**.
- **Namespace:** `namespace.yaml` (`oficina`).

### IaC — Terraform (`/infra`)
Provisiona a fundação AWS:
- **Rede:** VPC 10.0.0.0/16, subnets públicas/privadas (2 AZs), Internet Gateway, NAT Gateway, route tables.
- **EKS:** cluster (v1.31) + node group (t3.medium, 2–5) + IAM roles + security groups.
- **RDS:** PostgreSQL gerenciado + subnet group + security group (acesso só dos nodes EKS).
- **State:** S3 (tfstate) + DynamoDB (lock), ou Terraform Cloud.
- Documentação: `infra/README-infra.md`, `GUIA-DEPLOY-INFRA-TERRAFORM.md`, outputs em `infra/output.tf`.

### CI/CD (`.github/workflows/`)
- **`ci.yml`** — build (`mvnw verify`), testes + JaCoCo, SBOM (CycloneDX), Trivy.
- **`cd.yml`** — build da imagem Docker → push no **GHCR** → promoção por ambiente (STG → pré-prod → prod).
- **`deploy.yml`** — `kubectl apply` dos manifestos (namespace → configmap → secret → postgres → app+service → hpa), rollout do banco e da app, smoke test em `/actuator/health`.
- **`infra.yml`** — Terraform `plan`/`apply` (Terraform Cloud).

---

## 15. Como executar

### Local (Docker Compose)
```bash
docker-compose up --build
# API:      http://localhost:8080
# Swagger:  http://localhost:8080/swagger-ui.html
# Adminer:  http://localhost:8081
```
Login inicial: `admin@oficina.local` / `admin123` (configurável por env).
Para e-mail real, exporte `NOTIFICACAO_TIPO=smtp` + credenciais `MAIL_*` (ex.: Mailtrap) — ou use um arquivo `.env`.

### Kubernetes (Minikube ou EKS)
```bash
# Build da imagem antes do apply (imagePullPolicy: IfNotPresent)
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/          # configmap, secret, postgres, app, service, hpa
kubectl get pods -n oficina
```

### Provisionamento (Terraform)
```bash
cd infra
terraform init
terraform plan
terraform apply
# saída: eks_kubeconfig_command, rds_endpoint, etc.
```

> Guias detalhados no repositório: `README.md`, `README-BLOCO-G-CICD.md`, `infra/README-infra.md`, `GUIA-DEPLOY-INFRA-TERRAFORM.md`, `README-GUIA-VALIDACAO-K8S-TERRAFORM.md`.

---

## 16. Estrutura de diretórios

```
fiap-tech-challenge-oficina-mecanica-fase2/
├── src/main/java/br/com/oficina/   # código (domain, usecase, adapter, infrastructure)
├── src/main/resources/
│   ├── application.yml              # configuração Spring
│   └── db/migration/               # migrações Flyway (V1, V2)
├── src/test/java/br/com/oficina/   # testes (unit, integração, architecture)
├── k8s/                            # manifestos Kubernetes
├── infra/                          # scripts Terraform (VPC, EKS, RDS, state)
├── .github/workflows/              # pipelines CI/CD
├── Dockerfile                      # imagem multi-stage
├── docker-compose.yml              # ambiente local
├── pom.xml                         # dependências/plugins Maven
└── README.md + guias complementares
```
