# Bloco G — CI/CD Completo (Implementado + Validação)

Documento explicativo do **Bloco G** (CI/CD) e como validar.

> **Status:** implementado em `.github/workflows/cd.yml`. O esboço da seção 5 corresponde ao workflow real publicado.

---

## 1. O que o documento do trabalho pede

> **Integração Contínua/Entrega Contínua (CI/CD):**
> Pipeline de CI/CD configurada (GitHub Actions, GitLab CI, etc.), que execute:
> - Build da aplicação.
> - Execução dos testes automatizados.
> - Build da imagem Docker.
> - Deploy no cluster Kubernetes.
> - Deploy do banco de dados.
> - Aplicação dos manifestos YAML no cluster.

---

## 2. O que já existe hoje (`ci.yml`)

O pipeline atual já cobre **parte** dos requisitos:

| Etapa pedida | Job atual | Status |
|---|---|---|
| Build da aplicação | `build` (`./mvnw verify`) | ✅ Já existe |
| Execução dos testes | `build` (106 testes + JaCoCo) | ✅ Já existe |
| Build da imagem Docker | — | ❌ Falta |
| Deploy no cluster K8s | — | ❌ Falta |
| Deploy do banco de dados | — | ❌ Falta |
| Aplicação dos manifestos YAML | — | ❌ Falta |

> Bônus já presentes (não exigidos): geração de SBOM (CycloneDX) e scan de vulnerabilidades (Trivy).

---

## 3. O que será feito no Bloco G

Será criado um novo workflow **`cd.yml`** (Continuous Deployment) que complementa o `ci.yml` existente, adicionando os 4 passos que faltam:

| Passo | Job novo | O que faz |
|---|---|---|
| **G1** | `docker-build-push` | Build da imagem Docker (via Dockerfile multi-stage) e push para um registry (GitHub Container Registry — GHCR) |
| **G2** | `deploy` | Configura `kubectl`, aplica os manifestos do `/k8s` no cluster (namespace, configmap, secret, banco e aplicação), aguarda rollout |
| **G3** | (dentro do `deploy`) | Deploy do banco de dados (aplica `postgres-*.yaml`) + aplicação dos manifestos YAML (`kubectl apply -f k8s/`) |

### Por que GHCR (GitHub Container Registry)?
- Já integrado ao GitHub Actions (sem precisar configurar credenciais externas)
- O `GITHUB_TOKEN` nativo já tem permissão para push
- Gratuito para repositórios

---

## 4. Diagrama do Pipeline CI/CD

```
                            ┌─────────────────────────────────────────────┐
                            │          GATILHO (Trigger)                   │
                            │   push na main  OU  pull_request             │
                            └────────────────────┬────────────────────────┘
                                                 │
                  ┌──────────────────────────────┼──────────────────────────────┐
                  │                               │                              │
                  ▼                               ▼                              ▼
   ╔══════════════════════════╗   ╔══════════════════════════╗   ╔══════════════════════════╗
   ║   CI — ci.yml (existe)   ║   ║   CI — ci.yml (existe)   ║   ║   CI — ci.yml (existe)   ║
   ║                          ║   ║                          ║   ║                          ║
   ║  ┌────────────────────┐  ║   ║  ┌────────────────────┐  ║   ║  ┌────────────────────┐  ║
   ║  │ build              │  ║   ║  │ sbom (CycloneDX)   │  ║   ║  │ trivy (scan)       │  ║
   ║  │ • mvnw verify      │  ║   ║  │ • gera SBOM        │  ║   ║  │ • vulnerabilidades │  ║
   ║  │ • 106 testes       │  ║   ║  └────────────────────┘  ║   ║  └────────────────────┘  ║
   ║  │ • JaCoCo ≥ 80%     │  ║   ╚══════════════════════════╝   ╚══════════════════════════╝
   ║  └────────────────────┘  ║
   ╚════════════╤═════════════╝
                │ (sucesso + branch = main)
                ▼
   ╔════════════════════════════════════════════════════════════════════════════╗
   ║                       CD — cd.yml (NOVO — Bloco G)                          ║
   ║                                                                            ║
   ║  ┌──────────────────────────┐         ┌──────────────────────────────────┐ ║
   ║  │ G1: docker-build-push    │  ────▶  │ G2/G3: deploy                    │ ║
   ║  │                          │         │                                  │ ║
   ║  │ • docker build           │         │ • configura kubectl              │ ║
   ║  │   (Dockerfile)           │         │ • kubectl apply -f k8s/          │ ║
   ║  │ • tag :sha + :latest     │         │   ├─ namespace                   │ ║
   ║  │ • push p/ GHCR           │         │   ├─ configmap + secret          │ ║
   ║  │                          │         │   ├─ postgres (banco de dados)   │ ║
   ║  │ ghcr.io/<owner>/         │         │   ├─ app deployment + service    │ ║
   ║  │   oficina-backend:sha    │         │   └─ hpa                         │ ║
   ║  └──────────────────────────┘         │ • kubectl rollout status         │ ║
   ║                                       └──────────────────────────────────┘ ║
   ╚════════════════════════════════════════════════════════════════════════════╝
                                                 │
                                                 ▼
                            ┌─────────────────────────────────────────────┐
                            │       Cluster Kubernetes atualizado         │
                            │   (app + banco rodando com nova imagem)     │
                            └─────────────────────────────────────────────┘
```

---

## 5. Estrutura do `cd.yml` (esboço)

```yaml
name: CD

on:
  push:
    branches: [main]          # deploy apenas quando faz merge na main
  workflow_dispatch:           # permite disparo manual

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  # ─── G1: Build + Push da imagem Docker ───
  docker-build-push:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write          # necessário para push no GHCR
    outputs:
      image: ${{ steps.meta.outputs.tags }}
    steps:
      - uses: actions/checkout@v4
      - name: Login no GHCR
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - name: Build e Push
        uses: docker/build-push-action@v6
        with:
          context: .
          push: true
          tags: |
            ghcr.io/${{ github.repository }}:${{ github.sha }}
            ghcr.io/${{ github.repository }}:latest

  # ─── G2/G3: Deploy no Kubernetes ───
  deploy:
    runs-on: ubuntu-latest
    needs: docker-build-push
    steps:
      - uses: actions/checkout@v4
      - name: Configurar kubectl
        uses: azure/setup-kubectl@v4
      - name: Configurar acesso ao cluster
        run: |
          echo "${{ secrets.KUBECONFIG }}" | base64 -d > kubeconfig
          echo "KUBECONFIG=$PWD/kubeconfig" >> $GITHUB_ENV
      - name: Atualizar imagem no deployment
        run: |
          sed -i "s|image: oficina-backend:latest|image: ghcr.io/${{ github.repository }}:${{ github.sha }}|" k8s/app-deployment.yaml
      - name: Aplicar manifestos (banco + app)
        run: kubectl apply -f k8s/
      - name: Aguardar rollout
        run: |
          kubectl rollout status deployment/oficina-db -n oficina --timeout=120s
          kubectl rollout status deployment/oficina-app -n oficina --timeout=180s
```

---

## 6. Secrets necessários no GitHub

Para o pipeline de CD funcionar, será necessário configurar **1 secret** no repositório:

| Secret | Para quê | Como obter |
|---|---|---|
| `KUBECONFIG` | Acesso ao cluster K8s (base64) | `cat ~/.kube/config \| base64 -w0` |

> O `GITHUB_TOKEN` para push no GHCR é fornecido automaticamente pelo GitHub Actions — não precisa configurar.

Configuração: **Settings → Secrets and variables → Actions → New repository secret**

> **Comportamento sem cluster:** o job `docker-build-push` (G1) sempre roda e publica a imagem no GHCR. O job `deploy` (G2/G3) verifica se o secret `KUBECONFIG` existe; se **não** estiver configurado, as etapas de deploy são **puladas com um aviso** (`::warning::`) em vez de falhar o pipeline. Assim o CI/CD permanece verde mesmo sem um cluster ativo (útil para avaliação acadêmica), e o deploy automático é habilitado assim que o secret for adicionado.

---

## 7. Como Validar o Bloco G

### 7.1 — Validação da sintaxe do workflow (local)

```bash
# Instalar o actionlint (linter de GitHub Actions)
# https://github.com/rhysd/actionlint
actionlint .github/workflows/cd.yml
```

**Resultado esperado**: nenhum erro reportado.

### 7.2 — Validação do build/push da imagem (G1)

Após fazer merge na `main` (ou disparo manual via `workflow_dispatch`):

```
1. Acesse a aba "Actions" do repositório no GitHub
2. Abra a execução do workflow "CD"
3. Verifique o job "docker-build-push":
   ✅ Login no GHCR bem-sucedido
   ✅ Build da imagem concluído
   ✅ Push concluído
4. Confirme a imagem publicada em:
   https://github.com/<owner>/fiap-tech-challenge-oficina-mecanica-fase2/pkgs/container/fiap-tech-challenge-oficina-mecanica-fase2
```

### 7.3 — Validação do deploy (G2/G3)

```
1. No mesmo workflow, verifique o job "deploy":
   ✅ kubectl configurado
   ✅ kubectl apply -f k8s/ aplicou todos os recursos
   ✅ rollout status retornou "successfully rolled out"
```

### 7.4 — Validação no cluster (após deploy)

```bash
# Verificar que os pods estão rodando com a nova imagem
kubectl get pods -n oficina

# Confirmar que a imagem é a do GHCR (não a :latest local)
kubectl get deployment oficina-app -n oficina -o jsonpath='{.spec.template.spec.containers[0].image}'
# Esperado: ghcr.io/<owner>/fiap-tech-challenge-oficina-mecanica-fase2:<sha>

# Testar a aplicação
kubectl port-forward svc/oficina-app 8080:80 -n oficina
curl http://localhost:8080/actuator/health
# Esperado: {"status":"UP"}
```

### 7.5 — Checklist de Validação do Bloco G

| # | Validação | Onde verificar | Resultado esperado |
|---|---|---|---|
| 1 | Workflow dispara no push à main | Aba Actions | Execução "CD" iniciada |
| 2 | Build da imagem Docker | Job `docker-build-push` | Imagem buildada sem erro |
| 3 | Push para o registry | Job `docker-build-push` | Imagem no GHCR |
| 4 | kubectl conecta no cluster | Job `deploy` | `kubectl` autenticado |
| 5 | Manifestos aplicados | Job `deploy` | `created/configured` para todos |
| 6 | Banco de dados deployado | Job `deploy` | `oficina-db` rolled out |
| 7 | App deployado | Job `deploy` | `oficina-app` rolled out |
| 8 | Aplicação saudável | `curl /actuator/health` | `{"status":"UP"}` |

---

## 8. Fluxo Completo (CI → CD)

```
Desenvolvedor                GitHub                      Registry         Cluster K8s
     │                          │                            │                 │
     │  git push / PR           │                            │                 │
     ├─────────────────────────▶│                            │                 │
     │                          │  CI: build + testes        │                 │
     │                          │  (ci.yml)                  │                 │
     │                          │  ✅ 106 testes             │                 │
     │                          │                            │                 │
     │  merge na main           │                            │                 │
     ├─────────────────────────▶│                            │                 │
     │                          │  CD: docker build          │                 │
     │                          │  (cd.yml)                  │                 │
     │                          ├───────── push imagem ─────▶│                 │
     │                          │                            │                 │
     │                          │  kubectl apply -f k8s/     │                 │
     │                          ├────────────────────────────────────────────▶│
     │                          │                            │   deploy banco  │
     │                          │                            │   deploy app    │
     │                          │  rollout status            │   HPA ativo     │
     │                          │◀────────────────────────────────────────────┤
     │   ✅ Deploy concluído     │                            │                 │
     │◀─────────────────────────┤                            │                 │
```

---

## 9. Observações Importantes

- O **CD só roda na `main`** — pull requests apenas executam o CI (build + testes), evitando deploys acidentais.
- Em ambiente de avaliação acadêmica (sem cluster cloud sempre ligado), o job `deploy` pode ser:
  - Apontado para um cluster local (kind/minikube) via runner self-hosted, **ou**
  - Demonstrado no vídeo executando manualmente os mesmos comandos do `cd.yml`.
- A imagem é versionada por **SHA do commit** (rastreabilidade) além da tag `:latest`.
- O `workflow_dispatch` permite disparar o deploy manualmente pela interface do GitHub.
