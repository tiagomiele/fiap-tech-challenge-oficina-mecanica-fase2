# Changelog Detalhado — De/Para: Fase 1 → Fase 2

Este documento descreve **todas as mudanças realizadas** na evolução do projeto `fiap-tech-challenge-oficina-mecanica-fase2`, comparando a versão original (Fase 1 — monolito em camadas) com a nova versão (Fase 2 — Clean Architecture + evolução de APIs).

---

## Índice

- [1. Visão Geral das Mudanças](#1-visão-geral-das-mudanças)
- [2. Arquitetura: De Monolito em Camadas para Clean Architecture](#2-arquitetura-de-monolito-em-camadas-para-clean-architecture)
- [3. Reestruturação de Pacotes (De → Para)](#3-reestruturação-de-pacotes-de--para)
- [4. Gateways (novas interfaces)](#4-gateways-novas-interfaces)
- [5. Evolução da API — Bloco B1: Abertura Unificada de OS](#5-evolução-da-api--bloco-b1-abertura-unificada-de-os)
- [6. Evolução da API — Bloco B2: Listagem de OS Ativas com Prioridade](#6-evolução-da-api--bloco-b2-listagem-de-os-ativas-com-prioridade)
- [7. Evolução da API — Bloco B3: Notificação Fictícia](#7-evolução-da-api--bloco-b3-notificação-fictícia)
- [8. Testes: De 19 para 24 arquivos (97 → 106 testes)](#8-testes-de-19-para-24-arquivos-97--105-testes)
- [9. ArchUnit: De 3 para 5 testes](#9-archunit-de-3-para-4-testes)
- [10. StatusOrdemServico: Adição de Prioridade](#10-statusordemservico-adição-de-prioridade)
- [11. Dependências (pom.xml)](#11-dependências-pomxml)
- [12. Docker (docker-compose.yml)](#12-docker-docker-composeyml)
- [13. Resumo Numérico](#13-resumo-numérico)

---

## 1. Visão Geral das Mudanças

| Aspecto | Fase 1 (original) | Fase 2 (nova versão) |
|---|---|---|
| **Arquitetura** | Monolito em camadas flat (controller → service → domain) | **Clean Architecture 4 anéis** (infrastructure → adapter → usecase → domain) |
| **Pacotes principais** | `controller/`, `service/impl/`, `domain/`, `infrastructure/repository/`, `dto/`, `exception/` | `infrastructure/config/` (composition root), `adapter/` (controller, persistence, security, notification, dto, exception), `usecase/` (services + gateway/), `domain/` (model, enums, exception) |
| **Interfaces de saída** | `domain.repository.*` (14 interfaces no domínio) | `usecase.gateway.*` (16 interfaces — renomeadas + 3 novas) |
| **Abertura de OS** | Apenas `idCliente` + `placa` + `descricaoProblema` (itens adicionados depois) | **Unificada**: `idCliente` + `placa` + `descricaoProblema` + `itens[]` em uma só chamada |
| **Listagem de OS** | Sem endpoint dedicado para OS ativas | **Novo endpoint** `GET /ordens-servico/ativas` com ordenação por prioridade |
| **Notificação** | Não existia | **Notificação fictícia** via log SLF4J em cada transição de status |
| **Testes unitários** | 97 testes em 19 arquivos | **106 testes** em 24 arquivos (+4 integração E2E) |
| **ArchUnit** | 3 testes (camadas flat) | **5 testes** (Clean Architecture 4 anéis + isolamento usecase + isolamento adapter) |
| **CI** | 3 jobs | 3 jobs (inalterado) |

---

## 2. Arquitetura: De Monolito em Camadas para Clean Architecture

### ANTES (Fase 1) — Monolito em camadas flat

```
br.com.oficina
├── config/           ← Configurações Spring
├── controller/       ← 4 REST controllers
├── service/impl/     ← 11 services (lógica de negócio)
├── domain/
│   ├── model/        ← Entidades + Value Objects
│   ├── enums/        ← Enums de negócio
│   └── repository/   ← Interfaces de repositório (14 interfaces)
├── infrastructure/
│   ├── repository/   ← Entidades JPA + implementações
│   └── security/     ← JWT
├── dto/              ← DTOs (request/response)
├── mapper/           ← Conversores
└── exception/        ← Exceções + handler global
```

**Regra de dependência:**
```
controller → service → domain
infrastructure → domain
```

### DEPOIS (Fase 2) — Clean Architecture (4 Anéis)

```
br.com.oficina
├── domain/                    ← ANEL 1 — DOMAIN (puro, sem frameworks)
│   ├── model/                 ←   Entidades + Value Objects
│   ├── enums/                 ←   Enums de negócio
│   └── exception/             ←   BusinessException (movida de exception/)
├── usecase/                   ← ANEL 2 — USECASE (regras de aplicação)
│   ├── *ServiceImpl.java      ←   10 services (movidos de service/impl/)
│   └── gateway/               ←   16 interfaces (contratos de saída)
├── adapter/                   ← ANEL 3 — ADAPTER (interface adapters)
│   ├── controller/            ←   4 REST controllers (movidos de controller/)
│   ├── persistence/           ←   JPA entities + repositórios
│   ├── security/              ←   JWT (token service + filtro + properties)
│   ├── notification/          ←   LogNotificacaoGateway (NOVO)
│   ├── dto/                   ←   DTOs (movidos de dto/)
│   └── exception/             ←   ApiError + GlobalExceptionHandler + RequestIdFilter
├── infrastructure/            ← ANEL 4 — INFRASTRUCTURE (composition root)
│   └── config/                ←   SecurityConfig, AdminBootstrap, OpenApiConfig, SwaggerOrderConfig
```

**Regra de dependência (4 anéis):**
```
infrastructure → adapter → usecase → domain
(dependências sempre apontam para dentro)
```

---

## 3. Reestruturação de Pacotes (De → Para)

### Controllers

| Arquivo | DE (Fase 1) | PARA (Fase 2) |
|---|---|---|
| `AdministrativoOficinaController.java` | `controller/` | `adapter/controller/` |
| `AuthController.java` | `controller/` | `adapter/controller/` |
| `ClienteOficinaController.java` | `controller/` | `adapter/controller/` |
| `TecnicoOficinaController.java` | `controller/` | `adapter/controller/` |

### Services

| Arquivo | DE (Fase 1) | PARA (Fase 2) |
|---|---|---|
| `AuthServiceImpl.java` | `service/impl/` | `usecase/` |
| `ClienteServiceImpl.java` | `service/impl/` | `usecase/` |
| `EstoqueServiceImpl.java` | `service/impl/` | `usecase/` |
| `FinanceiroServiceImpl.java` | `service/impl/` | `usecase/` |
| `NotaFiscalFornecedorServiceImpl.java` | `service/impl/` | `usecase/` |
| `OrdemServicoServiceImpl.java` | `service/impl/` | `usecase/` |
| `PecaServiceImpl.java` | `service/impl/` | `usecase/` |
| `ServicoServiceImpl.java` | `service/impl/` | `usecase/` |
| `UserServiceImpl.java` | `service/impl/` | `usecase/` |
| `VeiculoServiceImpl.java` | `service/impl/` | `usecase/` |
| ~~`RelatorioServiceImpl.java`~~ | `service/impl/` | **REMOVIDO** (substituído por `RelatorioGateway`) |

### Interfaces de repositório

| Arquivo | DE (Fase 1) | PARA (Fase 2) |
|---|---|---|
| `ClienteRepository.java` | `domain/repository/` | `usecase/gateway/` |
| `EstoqueRepository.java` | `domain/repository/` | `usecase/gateway/` |
| `LancamentoFinanceiroRepository.java` | `domain/repository/` | `usecase/gateway/` |
| `NotaFiscalFornecedorRepository.java` | `domain/repository/` | `usecase/gateway/` |
| `NumeroOSGenerator.java` | `domain/repository/` | `usecase/gateway/` |
| `OrdemServicoRepository.java` | `domain/repository/` | `usecase/gateway/` |
| `OsAtivaPorClienteConsulta.java` | `domain/repository/` | `usecase/gateway/` |
| `OsAtivaPorPecaConsulta.java` | `domain/repository/` | `usecase/gateway/` |
| `OsAtivaPorServicoConsulta.java` | `domain/repository/` | `usecase/gateway/` |
| `OsAtivaPorVeiculoConsulta.java` | `domain/repository/` | `usecase/gateway/` |
| `PecaRepository.java` | `domain/repository/` | `usecase/gateway/` |
| `ServicoRepository.java` | `domain/repository/` | `usecase/gateway/` |
| `UserRepository.java` | `domain/repository/` | `usecase/gateway/` |
| `VeiculoRepository.java` | `domain/repository/` | `usecase/gateway/` |

### Implementações JPA

| Arquivos | DE (Fase 1) | PARA (Fase 2) |
|---|---|---|
| Todas as `*JpaEntity.java` (13 arquivos) | `infrastructure/repository/` | `adapter/persistence/` |
| Todas as `Jpa*Repository.java` (11 arquivos) | `infrastructure/repository/` | `adapter/persistence/` |
| Todas as `SpringData*Repository.java` (11 arquivos) | `infrastructure/repository/` | `adapter/persistence/` |
| Todas as `*IdJpa.java` (5 arquivos) | `infrastructure/repository/` | `adapter/persistence/` |
| Todas as `OsAtivaPor*Jpa.java` (4 arquivos) | `infrastructure/repository/` | `adapter/persistence/` |

### DTOs

| Arquivos | DE (Fase 1) | PARA (Fase 2) |
|---|---|---|
| `LancamentoResponse.java` | `dto/response/` | `adapter/dto/` |
| `OrdemServicoResponse.java` | `dto/response/` | `adapter/dto/` |
| `OrdemServicoStatusResponse.java` | `dto/response/` | `adapter/dto/` |
| `TempoMedioPorOsResponse.java` | `dto/response/` | `adapter/dto/` |

> **Nota**: os DTOs de `request` foram incorporados como `record` inline nos controllers (inner records).

### Exceções

| Arquivo | DE (Fase 1) | PARA (Fase 2) |
|---|---|---|
| `BusinessException.java` | `exception/` | `domain/exception/` |
| `ApiError.java` | `exception/` | `adapter/exception/` |
| `GlobalExceptionHandler.java` | `exception/` | `adapter/exception/` |

### Security

| Arquivo | DE (Fase 1) | PARA (Fase 2) |
|---|---|---|
| `JwtTokenService.java` | `adapter/security/` | `adapter/security/` (inalterado) |
| `JwtAuthenticationFilter.java` | `config/` → `infrastructure/security/` | `adapter/security/` |

---

## 4. Gateways (novas interfaces)

3 novas interfaces foram criadas na camada `usecase/gateway/` para desacoplar a camada de aplicação da infraestrutura:

| Interface | Responsabilidade | Implementação |
|---|---|---|
| **`TokenGateway`** | Gerar e validar tokens JWT | `JwtTokenService` (adapter/security) |
| **`RelatorioGateway`** | Consulta de tempo médio por OS | `JpaRelatorioRepository` (adapter/persistence) |
| **`NotificacaoGateway`** | Enviar notificações ao cliente | `LogNotificacaoGateway` (adapter/notification) |

### Por que criar Gateways?

Na Fase 1, os services dependiam diretamente das implementações concretas. Com os Gateways, a camada `usecase` define **apenas a interface** (contrato) — a implementação concreta fica na `infrastructure`, respeitando o princípio de **Inversão de Dependência (DIP)**.

```
ANTES: OrdemServicoServiceImpl → JpaRelatorioRepository (dependência direta)
DEPOIS: OrdemServicoServiceImpl → RelatorioGateway (interface) ← JpaRelatorioRepository (implementação)
```

---

## 5. Evolução da API — Bloco B1: Abertura Unificada de OS

### ANTES (Fase 1)

A abertura de uma OS exigia **múltiplas chamadas HTTP**:

```
1. POST /api/v1/ordens-servico         → cria OS (apenas cliente + veículo + descrição)
2. POST /ordens-servico/{id}/servicos   → adiciona cada serviço
3. POST /ordens-servico/{id}/pecas      → adiciona cada peça
```

**Request original (`POST /api/v1/ordens-servico`):**
```json
{
  "idCliente": 1,
  "placa": "ABC1234",
  "descricaoProblema": "Motor falhando"
}
```

### DEPOIS (Fase 2)

Uma única chamada cria a OS **já com os itens** no corpo da requisição:

```
1. POST /api/v1/ordens-servico  → cria OS com serviços e peças inclusos
```

**Request novo (`POST /api/v1/ordens-servico`):**
```json
{
  "idCliente": 1,
  "placa": "ABC1234",
  "descricaoProblema": "Motor falhando",
  "itens": [
    {
      "idServicoSku": 1,
      "tipo": "SERVICO",
      "quantidade": 1,
      "precoUnitario": 150.00
    },
    {
      "idServicoSku": 2,
      "tipo": "PECA",
      "quantidade": 2,
      "precoUnitario": 45.00
    }
  ]
}
```

**Resultado**: a OS é criada com status `EM_DIAGNOSTICO` (pois já contém itens), em vez de `RECEBIDA`. O campo `itens` é **opcional** — se omitido, a OS é criada normalmente como antes (status `RECEBIDA`), mantendo compatibilidade retroativa.

---

## 6. Evolução da API — Bloco B2: Listagem de OS Ativas com Prioridade

### ANTES (Fase 1)

Não existia um endpoint dedicado para listar OS ativas. A consulta era feita por ID ou número.

### DEPOIS (Fase 2)

**Novo endpoint**: `GET /ordens-servico/ativas`

**Características:**
- Retorna apenas OS com status **ativo** (exclui `ENTREGUE` e `CANCELADA`)
- Ordenadas por **prioridade de atendimento**:

| Status | Prioridade | Motivo |
|---|---|---|
| `EM_EXECUCAO` | 1 (mais urgente) | Reparo em andamento |
| `AGUARDANDO_APROVACAO` | 2 | Aguardando decisão do cliente |
| `EM_DIAGNOSTICO` | 3 | Em análise pelo técnico |
| `RECEBIDA` | 4 (menos urgente) | Recém-chegada |

**Mudança no `StatusOrdemServico`:**

```java
// ANTES (Fase 1) — enum simples
public enum StatusOrdemServico {
  RECEBIDA,
  EM_DIAGNOSTICO,
  AGUARDANDO_APROVACAO,
  EM_EXECUCAO,
  AGUARDANDO_PAGAMENTO,
  PAGA,
  ENTREGUE,
  CANCELADA
}

// DEPOIS (Fase 2) — com prioridade e filtro
public enum StatusOrdemServico {
  RECEBIDA(4),
  EM_DIAGNOSTICO(3),
  AGUARDANDO_APROVACAO(2),
  EM_EXECUCAO(1),
  AGUARDANDO_PAGAMENTO(5),
  PAGA(6),
  ENTREGUE(7),
  CANCELADA(8);

  private final int prioridadeListagem;

  StatusOrdemServico(int prioridadeListagem) {
    this.prioridadeListagem = prioridadeListagem;
  }

  public int getPrioridadeListagem() {
    return prioridadeListagem;
  }

  public boolean visivelNaListagem() {
    return this != ENTREGUE && this != CANCELADA;
  }
}
```

---

## 7. Evolução da API — Bloco B3: Notificação Fictícia

### ANTES (Fase 1)

Não existia nenhum mecanismo de notificação. As transições de status da OS ocorriam silenciosamente.

### DEPOIS (Fase 2)

A cada transição de status, o sistema envia uma **notificação fictícia** via log SLF4J. A implementação é propositalmente simples (sem dependência de serviço de e-mail externo) para demonstrar o padrão de Gateway.

**Nova interface** — `usecase/gateway/NotificacaoGateway.java`:
```java
public interface NotificacaoGateway {
  void enviar(String destinatario, String assunto, String corpo);
}
```

**Nova implementação** — `adapter/notification/LogNotificacaoGateway.java`:
```java
@Service
public class LogNotificacaoGateway implements NotificacaoGateway {
  private static final Logger log = LoggerFactory.getLogger(LogNotificacaoGateway.class);

  @Override
  public void enviar(String destinatario, String assunto, String corpo) {
    log.info(
        "[NOTIFICAÇÃO FICTÍCIA] Para: {} | Assunto: {} | Corpo: {}",
        destinatario, assunto, corpo);
  }
}
```

**Exemplo de log gerado:**
```
[NOTIFICAÇÃO FICTÍCIA] Para: cliente@email.com | Assunto: OS OS-052026-000001 — Status atualizado | Corpo: Sua OS mudou para: EM_DIAGNOSTICO
```

**Por que fictícia?** Para substituir facilmente por uma implementação real (e.g., Spring Mail, AWS SES, SendGrid) bastaria criar outra classe que implemente `NotificacaoGateway` — sem alterar nenhuma linha na camada `usecase`.

---

## 8. Testes: De 19 para 24 arquivos (97 → 106 testes)

### ANTES (Fase 1) — 19 arquivos, ~97 testes

```
src/test/java/br/com/oficina/
├── architecture/ArchitectureTest.java           (3 testes)
├── domain/model/
│   ├── ClienteTest.java
│   ├── DinheiroTest.java
│   ├── DocumentoTest.java
│   ├── EstoquePecaTest.java
│   ├── ItemOrcamentoTest.java
│   ├── LancamentoFinanceiroTest.java
│   ├── MovimentacaoEstoqueTest.java
│   ├── NotaFiscalFornecedorTest.java
│   ├── NumeroOSTest.java
│   ├── OrcamentoTest.java
│   ├── OrdemServicoTest.java
│   ├── PecaTest.java
│   ├── PlacaTest.java
│   ├── RaizDeAgregadoTest.java
│   ├── ServicoTest.java
│   ├── UserTest.java
│   └── VeiculoTest.java
└── exception/BusinessExceptionTest.java
```

### DEPOIS (Fase 2) — 24 arquivos, 106 testes (+5 arquivos, +8 testes)

```
src/test/java/br/com/oficina/
├── architecture/ArchitectureTest.java           (5 testes ← era 3)
├── domain/
│   ├── model/ (17 arquivos, inalterados)
│   └── exception/BusinessExceptionTest.java     (movido de exception/)
└── integration/                                 ← NOVO diretório
    ├── IntegrationTestBase.java                 ← NOVO (base com Testcontainers)
    ├── FluxoCompletoOsIntegrationTest.java      ← NOVO (fluxo completo de 10 passos)
    ├── ListagemAtivasIntegrationTest.java       ← NOVO (listagem ativas + prioridade)
    ├── NotaFiscalEstoqueIntegrationTest.java    ← NOVO (NF + estoque + financeiro)
    └── RejeicaoRefazerOsIntegrationTest.java    ← NOVO (rejeição + refazer orçamento)
```

### Detalhamento dos novos testes de integração

| Teste | O que valida | Tecnologia |
|---|---|---|
| `FluxoCompletoOsIntegrationTest` | Ciclo completo da OS em 10 passos: abrir → adicionar serviço → adicionar peça → enviar aprovação → aprovar → concluir → pagamento → entregar | Testcontainers + RestAssured + PostgreSQL 16 |
| `ListagemAtivasIntegrationTest` | Endpoint `GET /ordens-servico/ativas`: filtra OS finalizadas, ordena por prioridade de status | Testcontainers + RestAssured + PostgreSQL 16 |
| `NotaFiscalEstoqueIntegrationTest` | Registro de NF de fornecedor → entrada no estoque → geração de conta a pagar | Testcontainers + RestAssured + PostgreSQL 16 |
| `RejeicaoRefazerOsIntegrationTest` | Fluxo de rejeição de orçamento: rejeitar → refazer → novo orçamento → estorno de peças | Testcontainers + RestAssured + PostgreSQL 16 |

---

## 9. ArchUnit: De 3 para 5 testes

### ANTES (Fase 1) — 3 testes

| Teste | Regra validada |
|---|---|
| `camadasRespeitamDependencias()` | `controller` → `service` → `domain`; `infrastructure` → `domain` |
| `dominioNaoDependeDeSpring()` | `domain.model` não importa Spring, JPA, Servlet |
| `dominioNaoUsaJpa()` | `domain.model` não importa `jakarta.persistence`, `org.hibernate` |

### DEPOIS (Fase 2) — 5 testes

| Teste | Regra validada | Mudança |
|---|---|---|
| `cleanArchitecture4CamadasRespeitaDependencias()` | `infrastructure` → `adapter` → `usecase` → `domain` (4 anéis) | **REESCRITO** (4 camadas) |
| `dominioNaoDependeDeSpring()` | `domain` não importa Spring, JPA, Servlet | Inalterado |
| `dominioNaoUsaJpa()` | `domain` não importa JPA/Hibernate | Inalterado |
| `usecaseNaoDependeDeAdapterNemInfrastructure()` | `usecase` não pode importar nada de `adapter` nem `infrastructure` | **NOVO** |
| `adapterNaoDependeDeInfrastructure()` | `adapter` não pode importar nada de `infrastructure` | **NOVO** |

---

## 10. StatusOrdemServico: Adição de Prioridade

| Aspecto | ANTES | DEPOIS |
|---|---|---|
| Tipo | Enum simples (sem campos) | Enum com campo `prioridadeListagem` (int) |
| Métodos | Nenhum | `getPrioridadeListagem()`, `visivelNaListagem()` |
| Filtragem | Não existia | `visivelNaListagem()` retorna `false` para `ENTREGUE` e `CANCELADA` |

---

## 11. Dependências (pom.xml)

| Dependência | ANTES | DEPOIS |
|---|---|---|
| `spring-boot-starter-mail` | **Não existia** | **Não existe** (notificação é fictícia via log) |

> **Nota**: a dependência de mail nunca foi adicionada. A notificação fictícia usa apenas SLF4J (já incluído no Spring Boot starter).

---

## 12. Docker (docker-compose.yml)

| Aspecto | ANTES | DEPOIS |
|---|---|---|
| Serviços | `db`, `app`, `adminer` | `db`, `app`, `adminer` (inalterado) |
| Variáveis SMTP | Não existiam | Não existem (notificação é fictícia) |
| Dockerfile | Multi-stage (builder + runtime) | Multi-stage (inalterado) |

---

## 13. Resumo Numérico

| Métrica | Fase 1 | Fase 2 | Diferença |
|---|---|---|---|
| **Arquivos Java (src/main)** | ~80 | ~90 | +10 (gateways + notification + dto moves) |
| **Camadas arquiteturais** | 3 (flat) | 4 (domain, usecase, adapter, infrastructure) | +1 (adapter) |
| **Arquivos de teste** | 19 | 24 | +5 |
| **Total de testes** | 97 | 106 | +9 |
| **Testes ArchUnit** | 3 | 5 | +2 |
| **Testes de integração E2E** | 0 | 4 | +4 |
| **Interfaces Gateway** | 14 | 16 | +3 novas, -1 removida (RelatorioServiceImpl) |
| **Endpoints novos** | — | 1 (`GET /ordens-servico/ativas`) | +1 |
| **Endpoints modificados** | — | 1 (`POST /ordens-servico` com itens) | 1 evoluído |
| **Arquivos movidos** | — | ~80 (reorganização de pacotes) | — |
| **Build** | Verde (CI 3/3) | Verde (CI 3/3) | Mantido |
| **Cobertura JaCoCo** | ≥ 80% | ≥ 80% | Mantido |
| **Commits no PR** | — | 6 | — |
