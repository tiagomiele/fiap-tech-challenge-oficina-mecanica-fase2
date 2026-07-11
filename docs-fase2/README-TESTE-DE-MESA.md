# Teste de Mesa — Clean Architecture (4 Anéis)

Este documento apresenta um **teste de mesa** (desk test / trace) completo, percorrendo todos os 4 anéis da Clean Architecture durante a execução de um caso de uso real da aplicação: **Abertura Unificada de Ordem de Serviço**.

---

## Arquitetura — 4 Anéis

```
┌─────────────────────────────────────────────────────────────────┐
│  4. INFRASTRUCTURE  (anel externo — composition root)           │
│  SecurityConfig, AdminBootstrap, OpenApiConfig                  │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  3. ADAPTER  (interface adapters)                         │  │
│  │  Controllers, DTOs, JPA Repositories, JWT, Notification   │  │
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

### Regras de dependência

| Camada | Pode depender de | NÃO pode depender de |
|---|---|---|
| **Domain** | nada (Java puro) | usecase, adapter, infrastructure |
| **Usecase** | domain | adapter, infrastructure |
| **Adapter** | usecase, domain | infrastructure |
| **Infrastructure** | adapter, usecase, domain | — |

### Mapeamento de pacotes

| Anel | Pacote Java | Conteúdo |
|---|---|---|
| **1. Domain** | `br.com.oficina.domain.model` | `OrdemServico`, `Cliente`, `Dinheiro`, `Placa`, `NumeroOS`, etc. |
| | `br.com.oficina.domain.enums` | `StatusOrdemServico`, `TipoItem`, etc. |
| | `br.com.oficina.domain.exception` | `BusinessException` |
| **2. Usecase** | `br.com.oficina.usecase` | `OrdemServicoServiceImpl`, `ClienteServiceImpl`, etc. |
| | `br.com.oficina.usecase.gateway` | `OrdemServicoRepository`, `NotificacaoGateway`, `TokenGateway`, etc. |
| **3. Adapter** | `br.com.oficina.adapter.controller` | `AdministrativoOficinaController`, `AuthController`, etc. |
| | `br.com.oficina.adapter.dto` | `OrdemServicoResponse`, `LancamentoResponse`, etc. |
| | `br.com.oficina.adapter.persistence` | `JpaOrdemServicoRepository`, `OrdemServicoJpaEntity`, etc. |
| | `br.com.oficina.adapter.security` | `JwtTokenService`, `JwtAuthenticationFilter`, `JwtProperties` |
| | `br.com.oficina.adapter.notification` | `LogNotificacaoGateway` |
| | `br.com.oficina.adapter.exception` | `GlobalExceptionHandler`, `ApiError`, `RequestIdFilter` |
| **4. Infrastructure** | `br.com.oficina.infrastructure.config` | `SecurityConfig`, `AdminBootstrap`, `OpenApiConfig`, `SwaggerOrderConfig` |

---

## Caso de Uso: Abertura Unificada de OS com Itens

**Cenário**: O funcionário da oficina abre uma nova OS para um cliente, já incluindo um serviço de "Troca de óleo" no corpo da requisição.

### Dados de entrada

```http
POST /api/v1/ordens-servico
Authorization: Bearer eyJhbGciOiJIUzI1NiI...
Content-Type: application/json

{
  "idCliente": 1,
  "placa": "ABC1D23",
  "descricaoProblema": "Motor falhando ao dar partida",
  "itens": [
    {
      "idServicoSku": 1,
      "tipo": "SERVICO",
      "quantidade": 1,
      "precoUnitario": 150.00
    }
  ]
}
```

---

## Trace — Passo a Passo pelos 4 Anéis

### PASSO 1 — INFRASTRUCTURE (anel 4): Autenticação e roteamento

**Arquivo**: `infrastructure/config/SecurityConfig.java`

```
→ Requisição HTTP chega ao Spring Boot
→ JwtAuthenticationFilter (adapter/security) intercepta
→ Extrai o token JWT do header Authorization
→ Valida assinatura HMAC-SHA256 usando JwtProperties.secret
→ Obtém email e roles do token (ex: FUNCIONARIO_DA_OFICINA)
→ Cria SecurityContext autenticado
→ Spring Security verifica @PreAuthorize("hasRole('FUNCIONARIO_DA_OFICINA')") ✓
→ Roteia para AdministrativoOficinaController.abrirOs()
```

| Estado | Valor |
|---|---|
| Token válido | `true` |
| Papel do usuário | `FUNCIONARIO_DA_OFICINA` |
| Acesso autorizado | `true` |

---

### PASSO 2 — ADAPTER (anel 3): Controller recebe e converte

**Arquivo**: `adapter/controller/AdministrativoOficinaController.java` (linha ~666)

```java
@PostMapping("/ordens-servico")
public ResponseEntity<OrdemServicoResponse> abrirOs(@Valid @RequestBody AbrirOsRequest req) {
    // 2.1 — Jakarta Validation valida o body (campos @NotNull, @NotBlank, etc.)
    // 2.2 — Converte DTOs do adapter para objetos do usecase
    List<OrdemServicoServiceImpl.ItemAbertura> itens =
        req.itens().stream()
            .map(i -> new OrdemServicoServiceImpl.ItemAbertura(
                i.idServicoSku(), i.tipo(), i.quantidade(), i.precoUnitario()))
            .toList();
    // 2.3 — Chama o caso de uso (próximo anel)
    OrdemServico os = osService.abrir(req.idCliente(), req.placa(), req.descricaoProblema(), itens);
    // 2.7 (retorno) — Converte entidade de domínio → DTO de resposta
    return ResponseEntity.status(HttpStatus.CREATED).body(OrdemServicoResponse.de(os));
}
```

| Estado | Valor |
|---|---|
| `req.idCliente` | `1` |
| `req.placa` | `"ABC1D23"` |
| `req.descricaoProblema` | `"Motor falhando ao dar partida"` |
| `req.itens[0]` | `{idServicoSku=1, tipo=SERVICO, qtd=1, preco=150.00}` |
| Validação Jakarta | `✓ Passou` |

**Fluxo**: Adapter → Usecase (chamada `osService.abrir(...)`)

---

### PASSO 3 — USECASE (anel 2): Orquestra regras de aplicação

**Arquivo**: `usecase/OrdemServicoServiceImpl.java` (linhas 63–78 e 81–98)

```java
@Transactional
public OrdemServico abrir(Long idCliente, String placaRaw, String descricaoProblema,
                          List<ItemAbertura> itens) {
    // 3.1 — Chama o método de abertura simples
    OrdemServico os = abrir(idCliente, placaRaw, descricaoProblema);
    
    // 3.2 — Para cada item, adiciona serviço ou peça
    for (ItemAbertura item : itens) {
        if (item.tipo() == TipoItem.SERVICO) {
            os = adicionarServico(numero, item.idServicoSku(), item.quantidade(), item.precoUnitario());
        } else {
            os = adicionarPeca(numero, item.idServicoSku(), item.quantidade(), item.precoUnitario());
        }
    }
    return os;
}

public OrdemServico abrir(Long idCliente, String placaRaw, String descricaoProblema) {
    // 3.1a — Busca cliente via Gateway (interface)
    Cliente cliente = clientes.porId(idCliente)
        .orElseThrow(() -> new BusinessException("CLIENTE_NAO_CADASTRADO", "..."));
    
    // 3.1b — Valida que cliente está ativo (regra de aplicação)
    if (!cliente.isAtivo()) throw new BusinessException("CLIENTE_INATIVO", "...");
    
    // 3.1c — Cria Value Object Placa (validação no domínio)
    Placa placa = Placa.de(placaRaw);  // → vai para DOMAIN
    
    // 3.1d — Verifica veículo existe via Gateway
    VeiculoId vid = new VeiculoId(placa, idCliente);
    if (veiculos.porId(vid).isEmpty())
        throw new BusinessException("VEICULO_NAO_CADASTRADO", "...");
    
    // 3.1e — Gera número OS via Gateway
    NumeroOS numero = numerador.proximo();  // → vai para ADAPTER (persistence)
    
    // 3.1f — Cria OS via factory method do domínio
    OrdemServico os = OrdemServico.abrir(numero, idCliente, placa, descricaoProblema);  // → DOMAIN
    
    // 3.1g — Persiste via Gateway
    return repo.salvar(os);  // → vai para ADAPTER (persistence)
}
```

**Interfaces Gateway usadas (definidas em `usecase/gateway/`):**

| Gateway (interface) | Implementação (adapter) | Operação |
|---|---|---|
| `ClienteRepository.porId(1)` | `JpaClienteRepository` | Busca cliente no PostgreSQL |
| `VeiculoRepository.porId(vid)` | `JpaVeiculoRepository` | Verifica veículo existe |
| `NumeroOSGenerator.proximo()` | `JpaNumeroOSGenerator` | Gera `OS-052026-000001` via sequência no banco |
| `OrdemServicoRepository.salvar(os)` | `JpaOrdemServicoRepository` | Persiste OS no PostgreSQL |
| `ServicoRepository.porId(1)` | `JpaServicoRepository` | Busca serviço para adicionar ao orçamento |

| Estado após Passo 3 | Valor |
|---|---|
| Cliente encontrado | `Cliente{id=1, nome="João Silva", ativo=true}` |
| Placa validada (Mercosul) | `Placa("ABC1D23")` |
| Veículo encontrado | `true` |
| Número OS gerado | `NumeroOS("OS-052026-000001")` |
| OS criada (fábrica de domínio) | `OrdemServico{status=RECEBIDA}` |
| Após adicionar serviço | `OrdemServico{status=EM_DIAGNOSTICO, itens=[1]}` |

---

### PASSO 4 — DOMAIN (anel 1): Regras de negócio puras

**Arquivo**: `domain/model/OrdemServico.java` (linhas 65–83)

```java
// 4.1 — Factory method: cria OS com status RECEBIDA
public static OrdemServico abrir(NumeroOS numero, Long idCliente, Placa placa, String descricao) {
    Instant agora = Instant.now();
    return new OrdemServico(
        numero, idCliente, placa,
        StatusOrdemServico.RECEBIDA,  // ← estado inicial
        descricao,
        Dinheiro.ZERO,                // ← valor total começa em R$ 0,00
        null, null,                   // ← sem motivo rejeição, sem comprovante
        new ArrayList<>(),            // ← lista de itens vazia
        1,                            // ← orçamento nº 1
        agora, agora,                 // ← criadoEm = atualizadoEm = agora
        null, null                    // ← sem início/fim execução
    );
}
```

**Arquivo**: `domain/model/Placa.java`

```java
// 4.2 — Value Object valida formato da placa
public static Placa de(String valor) {
    // Aceita formato antigo (ABC1234) e Mercosul (ABC1D23)
    // Lança BusinessException se formato inválido
    // "ABC1D23" → formato Mercosul → ✓ válido
}
```

**Arquivo**: `domain/model/OrdemServico.java` (linhas 135–165) — quando o item é adicionado:

```java
// 4.3 — Adiciona item ao orçamento (transição de status)
public void adicionarItem(ItemOrcamento item) {
    if (status != RECEBIDA && status != EM_DIAGNOSTICO) {
        throw new BusinessException("ORDEM_SERVICO_STATUS_INVALIDO",
            "Itens só podem ser adicionados em RECEBIDA ou EM_DIAGNOSTICO");
    }
    if (status == RECEBIDA) {
        status = EM_DIAGNOSTICO;  // ← TRANSIÇÃO AUTOMÁTICA
    }
    itens.add(item);
    recalcularTotal();
    atualizadoEm = Instant.now();
}
```

**Arquivo**: `domain/enums/StatusOrdemServico.java`

```java
// 4.4 — Enum com prioridade para listagem
public enum StatusOrdemServico {
    RECEBIDA(4),
    EM_DIAGNOSTICO(3),       // ← status após adicionar item
    AGUARDANDO_APROVACAO(2),
    EM_EXECUCAO(1),
    ...
}
```

| Estado do Domain | Valor |
|---|---|
| `Placa.de("ABC1D23")` | `Placa{valor="ABC1D23", formato=MERCOSUL}` |
| `NumeroOS{valor}` | `"OS-052026-000001"` |
| `Dinheiro.ZERO` | `Dinheiro{valor=0.00}` |
| Status inicial | `RECEBIDA` |
| Status após `adicionarItem()` | `EM_DIAGNOSTICO` (transição automática) |
| `valorTotalConserto` | `Dinheiro{valor=150.00}` (recalculado) |
| `itens.size()` | `1` |
| `orcamentoAtual` | `1` |

---

### PASSO 5 — ADAPTER (anel 3): Persistência (saída)

**Arquivo**: `adapter/persistence/JpaOrdemServicoRepository.java` (linhas 26–65)

```java
// 5.1 — Implementa a interface OrdemServicoRepository (usecase/gateway)
@Component
public class JpaOrdemServicoRepository implements OrdemServicoRepository {

    @Override
    public OrdemServico salvar(OrdemServico os) {
        // 5.1a — Converte entidade de domínio → entidade JPA
        OrdemServicoJpaEntity entity = ...;
        entity.setStatus(os.getStatus());           // EM_DIAGNOSTICO
        entity.setValorTotalConserto(os.getValorTotalConserto().valor()); // 150.00
        
        // 5.1b — Sincroniza itens do orçamento (merge)
        for (ItemOrcamento it : os.getItens()) {
            ItemOrcamentoJpaEntity ij = ...;
            ij.setTipo(it.getTipo());               // SERVICO
            ij.setPrecoUnitario(it.getPrecoUnitario().valor()); // 150.00
            entity.getItens().add(ij);
        }
        
        // 5.1c — Persiste via Spring Data JPA → PostgreSQL
        repo.save(entity);
        
        // 5.1d — Reconstrói entidade de domínio a partir da JPA (com ID gerado)
        return reconstituir(entity);
    }
}
```

| Estado no banco (PostgreSQL) | Valor |
|---|---|
| `ordens_servico.numero_os` | `"OS-052026-000001"` |
| `ordens_servico.id_cliente` | `1` |
| `ordens_servico.id_placa` | `"ABC1D23"` |
| `ordens_servico.status` | `"EM_DIAGNOSTICO"` |
| `ordens_servico.descricao_problema` | `"Motor falhando ao dar partida"` |
| `ordens_servico.valor_total_conserto` | `150.00` |
| `ordens_servico.orcamento_atual` | `1` |
| `orcamentos_itens_ordem_servico[0].tipo` | `"SERVICO"` |
| `orcamentos_itens_ordem_servico[0].preco_unitario` | `150.00` |

---

### PASSO 6 — ADAPTER (anel 3): Resposta HTTP (saída)

**Arquivo**: `adapter/dto/OrdemServicoResponse.java`

```java
// 6.1 — Converte entidade de domínio → DTO de resposta
public static OrdemServicoResponse de(OrdemServico os) {
    return new OrdemServicoResponse(
        os.getNumero().valor(),          // "OS-052026-000001"
        os.getIdCliente(),               // 1
        os.getPlaca().valor(),           // "ABC1D23"
        os.getStatus().name(),           // "EM_DIAGNOSTICO"
        os.getDescricaoProblema(),       // "Motor falhando ao dar partida"
        os.getValorTotalConserto().valor(), // 150.00
        itens...                         // lista de itens do orçamento
    );
}
```

**Resposta HTTP final:**

```http
HTTP/1.1 201 Created
Content-Type: application/json

{
  "numero": "OS-052026-000001",
  "idCliente": 1,
  "placa": "ABC1D23",
  "status": "EM_DIAGNOSTICO",
  "descricaoProblema": "Motor falhando ao dar partida",
  "valorTotalConserto": 150.00,
  "itens": [
    {
      "idOrcamento": 1,
      "idOrcamentoItem": 1,
      "tipo": "SERVICO",
      "idServico": 1,
      "quantidade": 1,
      "precoUnitario": 150.00,
      "status": "EM_ANALISE"
    }
  ]
}
```

---

## Diagrama de Sequência Completo

```
  Cliente HTTP          INFRASTRUCTURE         ADAPTER                  USECASE                     DOMAIN
  ──────────          ──────────────          ────────                  ────────                     ──────
       │                    │                    │                         │                           │
       │  POST /ordens-     │                    │                         │                           │
       │  servico           │                    │                         │                           │
       │───────────────────>│                    │                         │                           │
       │                    │                    │                         │                           │
       │                    │ JwtAuthFilter      │                         │                           │
       │                    │ valida token       │                         │                           │
       │                    │ SecurityConfig     │                         │                           │
       │                    │ verifica role      │                         │                           │
       │                    │                    │                         │                           │
       │                    │  roteia para       │                         │                           │
       │                    │─────────────────-->│                         │                           │
       │                    │                    │ Controller.abrirOs()    │                           │
       │                    │                    │ converte DTO → record   │                           │
       │                    │                    │                         │                           │
       │                    │                    │ osService.abrir()       │                           │
       │                    │                    │────────────────────────>│                           │
       │                    │                    │                         │                           │
       │                    │                    │                         │ clientes.porId(1)         │
       │                    │                    │<─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ │ (via Gateway interface)   │
       │                    │                    │ JpaClienteRepository    │                           │
       │                    │                    │ → SELECT FROM clientes  │                           │
       │                    │                    │ → retorna Cliente       │                           │
       │                    │                    │─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─>│                           │
       │                    │                    │                         │                           │
       │                    │                    │                         │ Placa.de("ABC1D23")       │
       │                    │                    │                         │──────────────────────────>│
       │                    │                    │                         │     Value Object criado   │
       │                    │                    │                         │<──────────────────────────│
       │                    │                    │                         │                           │
       │                    │                    │                         │ numerador.proximo()       │
       │                    │                    │<─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ │ (via Gateway interface)   │
       │                    │                    │ JpaNumeroOSGenerator    │                           │
       │                    │                    │ → SELECT + UPDATE seq   │                           │
       │                    │                    │ → retorna NumeroOS      │                           │
       │                    │                    │─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─>│                           │
       │                    │                    │                         │                           │
       │                    │                    │                         │ OrdemServico.abrir(...)    │
       │                    │                    │                         │──────────────────────────>│
       │                    │                    │                         │  cria OS status=RECEBIDA  │
       │                    │                    │                         │<──────────────────────────│
       │                    │                    │                         │                           │
       │                    │                    │                         │ os.adicionarItem(item)    │
       │                    │                    │                         │──────────────────────────>│
       │                    │                    │                         │  RECEBIDA → EM_DIAGNOSTICO│
       │                    │                    │                         │  recalcula total = 150.00 │
       │                    │                    │                         │<──────────────────────────│
       │                    │                    │                         │                           │
       │                    │                    │                         │ repo.salvar(os)           │
       │                    │                    │<─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ │ (via Gateway interface)   │
       │                    │                    │ JpaOrdemServicoRepo     │                           │
       │                    │                    │ → INSERT ordens_servico │                           │
       │                    │                    │ → INSERT orcam_itens    │                           │
       │                    │                    │ → retorna OS persistida │                           │
       │                    │                    │─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─>│                           │
       │                    │                    │                         │                           │
       │                    │                    │<────────────────────────│ retorna OrdemServico      │
       │                    │                    │                         │                           │
       │                    │                    │ OrdemServicoResponse    │                           │
       │                    │                    │ .de(os) → converte DTO  │                           │
       │                    │                    │                         │                           │
       │<───────────────────│────────────────────│                         │                           │
       │  HTTP 201 Created  │                    │                         │                           │
       │  { "numero": "OS-" │                    │                         │                           │
       │    "status":        │                    │                         │                           │
       │    "EM_DIAGNOSTICO"}│                    │                         │                           │
```

---

## Inversão de Dependência em Ação

O ponto central da Clean Architecture é a **Inversão de Dependência (DIP)**. No nosso caso:

```
                  DEFINE a interface               IMPLEMENTA a interface
                  ─────────────────               ──────────────────────
                                                  
  ┌────────────────────────────┐          ┌──────────────────────────────────┐
  │        USECASE             │          │            ADAPTER               │
  │                            │          │                                  │
  │  OrdemServicoServiceImpl   │          │  JpaOrdemServicoRepository       │
  │    usa: repo.salvar(os)    │          │    implements OrdemServicoRepo   │
  │                            │          │    usa: SpringData + JPA Entity  │
  │  ┌──────────────────────┐  │          │                                  │
  │  │ interface             │  │  ◄──────│  @Component                      │
  │  │ OrdemServicoRepository│  │          │  class JpaOrdemServicoRepository │
  │  │   salvar(OrdemServico)│  │          │    implements OrdemServicoRepo   │
  │  └──────────────────────┘  │          └──────────────────────────────────┘
  └────────────────────────────┘
  
  O usecase NÃO conhece JPA.
  O usecase NÃO conhece Spring Data.
  O usecase NÃO conhece PostgreSQL.
  
  Ele conhece apenas a INTERFACE (Gateway).
  A implementação concreta é injetada pelo Spring (Infrastructure → composition root).
```

### Benefícios demonstrados neste teste de mesa:

1. **Domain puro**: `OrdemServico.abrir()`, `Placa.de()`, `StatusOrdemServico` — nenhuma dependência de framework.
2. **Usecase orquestra sem conhecer infraestrutura**: `OrdemServicoServiceImpl` usa `ClienteRepository`, `OrdemServicoRepository`, `NotificacaoGateway` — apenas interfaces.
3. **Adapter traduz**: `AdministrativoOficinaController` converte HTTP → objetos de domínio; `JpaOrdemServicoRepository` converte domínio → JPA.
4. **Infrastructure configura**: `SecurityConfig` monta o filtro JWT, `AdminBootstrap` cria o admin inicial — apenas wiring.
5. **Testabilidade**: o domínio pode ser testado sem Spring (97 testes unitários puros). Os usecases podem ser testados com mocks dos gateways.

---

## Validação Automatizada — ArchUnit (5 testes)

As regras de dependência dos 4 anéis são validadas automaticamente a cada build:

| # | Teste ArchUnit | O que valida |
|---|---|---|
| 1 | `cleanArchitecture4CamadasRespeitaDependencias()` | Dependências entre as 4 camadas respeitam a direção correta |
| 2 | `dominioNaoDependeDeSpring()` | `domain` não importa Spring, JPA ou Servlet |
| 3 | `dominioNaoUsaJpa()` | `domain` não importa `jakarta.persistence` ou `org.hibernate` |
| 4 | `usecaseNaoDependeDeAdapterNemInfrastructure()` | `usecase` não importa nada de `adapter` nem `infrastructure` |
| 5 | `adapterNaoDependeDeInfrastructure()` | `adapter` não importa nada de `infrastructure` |

**Localização**: `src/test/java/br/com/oficina/architecture/ArchitectureTest.java`

---

## Tabela Resumo — Fluxo pelo 4 Anéis

| Passo | Anel | Classe | Método | Entrada | Saída |
|---|---|---|---|---|---|
| 1 | Infrastructure | `SecurityConfig` + `JwtAuthenticationFilter` | filtro HTTP | Token JWT | SecurityContext autenticado |
| 2 | Adapter | `AdministrativoOficinaController` | `abrirOs()` | `AbrirOsRequest` (DTO) | chama `osService.abrir()` |
| 3a | Usecase | `OrdemServicoServiceImpl` | `abrir()` | idCliente, placa, descrição, itens | busca cliente, valida, gera nº OS |
| 3b | Usecase | `OrdemServicoServiceImpl` | via Gateway | `ClienteRepository.porId()` | `Cliente` |
| 3c | Usecase | `OrdemServicoServiceImpl` | via Gateway | `NumeroOSGenerator.proximo()` | `NumeroOS("OS-052026-000001")` |
| 4a | Domain | `Placa` | `de("ABC1D23")` | String | `Placa` (Value Object validado) |
| 4b | Domain | `OrdemServico` | `abrir(...)` | NumeroOS, idCliente, Placa, desc | `OrdemServico{status=RECEBIDA}` |
| 4c | Domain | `OrdemServico` | `adicionarItem()` | ItemOrcamento | status → `EM_DIAGNOSTICO`, total=150 |
| 5 | Adapter | `JpaOrdemServicoRepository` | `salvar()` | `OrdemServico` (domínio) | INSERT → PostgreSQL, retorna OS |
| 6 | Adapter | `OrdemServicoResponse` | `de()` | `OrdemServico` (domínio) | JSON → HTTP 201 Created |
