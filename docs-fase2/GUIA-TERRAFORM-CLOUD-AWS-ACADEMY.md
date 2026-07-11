# Guia — Automatizar a subida da infra com Terraform Cloud + GitHub (AWS Academy)

> **Para quem é este guia:** alguém que nunca usou Terraform Cloud. Cada passo
> explica **o que** você faz e **por quê**. Leia na ordem.

---

## 1. O que vamos montar (visão geral)

Hoje você sobe a infra **manualmente** no terminal do AWS Academy (o Runbook:
`terraform init/plan/apply` na mão). A ideia agora é tirar esse trabalho manual
e deixar o **Terraform Cloud** fazer por você.

**Terraform Cloud (HCP Terraform)** é um serviço gratuito da HashiCorp que:

- guarda o **state** do Terraform na nuvem (você não depende mais do arquivo
  `terraform.tfstate` na sua máquina);
- **executa** o `terraform plan` e o `terraform apply` nos servidores deles;
- guarda as **credenciais da AWS** num cofre (Variables), com segurança;
- dispara tudo a partir de um **push no GitHub** — você só aprova o apply.

### Desenho do fluxo

```
   Você edita infra/*.tf  ->  git push  ->  GitHub
                                              │
                                              ▼
                                    Terraform Cloud (workspace)
                                    - usa as credenciais AWS guardadas
                                    - roda plan  -> você revisa
                                    - roda apply -> você clica "Confirm"
                                              │
                                              ▼
                                      AWS  (VPC + EKS + RDS)
```

> **Importante (limitação do AWS Academy):** as credenciais do Learner Lab
> **expiram a cada sessão** (mudam toda vez que você abre o lab). Então, mesmo
> com a automação, **uma coisa continua manual:** atualizar as 3 credenciais no
> Terraform Cloud sempre que abrir o lab. Em uma conta AWS de verdade isso seria
> 100% automático e você nunca mais mexeria. O **Passo 6** mostra exatamente
> onde colar essas credenciais.

---

## ⚡ Atalho — Checklist rápido (quando você JÁ configurou uma vez)

Se já fez a configuração inicial (Passos 1 a 3) numa execução anterior, **toda vez
que reabrir o lab** o roteiro é só este. Os detalhes de cada item estão nas seções
indicadas.

```
[ ] 1. Abrir o lab no AWS Academy e clicar "Start Lab" (bolinha verde).
[ ] 2. AWS Details → AWS CLI → Show → copiar os 3 valores.
[ ] 3. Terraform Cloud → workspace → Variables → ATUALIZAR os 3
       Environment variables (AWS_ACCESS_KEY_ID / SECRET / SESSION_TOKEN).   (Passo 4.2)
[ ] 4. Conferir o Account ID: aws sts get-caller-identity
       Se mudou, ajustar lab_role_arn e access_entry_role_arn no workspace.   (Passo 4.3)
[ ] 5. Terraform Cloud → Actions → Start new run (ou git push) → Confirm & Apply.
       Espera ~15-20 min. Deve terminar "Apply complete! 23 resources added".  (Passo 5)
[ ] 6. aws eks update-kubeconfig --region us-west-2 --name oficina-dev
       kubectl get nodes   (2 nós Ready)                                       (Passo 6)
[ ] 7. ./k8s/deploy-aws-academy.ps1 -DbPassword "<sua-senha-do-rds>"           (Passo 6)
[ ] 8. kubectl get svc oficina-app -n oficina  → abrir http://<ELB>/swagger-ui/index.html
[ ] 9. AO TERMINAR: kubectl delete svc oficina-app -n oficina  (libera o ELB)
       → Terraform Cloud → Settings → Destruction → digitar "delete" → destroy. (Passo 7)
[ ] 10. AWS Academy → End Lab.
```

> 💡 **Os 3 erros que mais travam (e a regra de ouro de cada um):**
> 1. **Credenciais expiradas** → sempre reatualize os 3 valores no Passo 4.2 ao abrir o lab.
> 2. **`kubectl` recusa acesso** → `access_entry_role_arn` tem que ser **`voclabs`**, não `LabRole`.
> 3. **App em `CrashLoopBackOff`** → use o script `deploy-aws-academy.ps1` (não `kubectl apply -f k8s/`); ele aponta pro RDS e evita o bug do `DB_URL` vazio.

---

## 2. Pré-requisitos

- Conta no GitHub com o repositório `fiap-tech-challenge-oficina-mecanica-fase2` (já tem).
- Lab do AWS Academy aberto (para pegar as credenciais quando for a hora).
- (Opcional) Terraform instalado na máquina, só se quiser testar pelo terminal.

Você **não** precisa instalar nada para a automação funcionar — ela roda na
nuvem.

---

## 3. Passo 1 — Criar a conta e a organização no Terraform Cloud

1. Acesse **https://app.terraform.io/signup/account** e crie uma conta grátis.
2. Confirme o e-mail e faça login em **https://app.terraform.io**.
3. Na primeira vez ele pede para **criar uma organização** (*organization*).
   - Dê um nome único, por exemplo: `oficina-fiap-SEUNOME`.
   - **Anote esse nome** — vamos usar como `TF_CLOUD_ORGANIZATION`.

> *O que é uma organização?* É só o "espaço" da sua conta onde ficam os
> workspaces. Pense como uma pasta-raiz.

---

## 4. Passo 2 — Criar o workspace conectado ao GitHub (VCS-driven)

Um **workspace** é onde o Terraform Cloud roda a sua infra. Vamos criar um do
tipo **"Version Control Workflow"**, que fica observando o seu repositório.

1. No Terraform Cloud, clique em **New** → **Workspace**.
2. Escolha **Version Control Workflow**.
3. Conecte sua conta do **GitHub** (ele abre uma tela de autorização do GitHub —
   aprove o acesso ao repositório `fiap-tech-challenge-oficina-mecanica-fase2`).
4. Selecione o repositório `fiap-tech-challenge-oficina-mecanica-fase2`.
5. **Workspace Name:** digite `oficina-backend-infra`
   - **Anote** — é o `TF_WORKSPACE`.
6. Clique em **Advanced options** e ajuste:
   - **Terraform Working Directory:** `infra`
     *(é a pasta onde estão os `.tf`; sem isso o TFC não acha os arquivos.)*
   - **Apply Method:** deixe em **Manual apply**
     *(assim você sempre revisa o plan e clica para aplicar — mais seguro.)*
7. Clique em **Create**.

> A partir daqui, todo `git push` que mexer em `infra/` faz o Terraform Cloud
> rodar um `plan` automaticamente.

---

## 5. Passo 3 — Ligar o bloco `cloud {}` no código

Para o Terraform usar o Terraform Cloud (em vez do state local), precisamos
ativar um pequeno bloco no código.

1. Abra o arquivo **`infra/backend.tf`**.
2. **Descomente** (tire o `#`) apenas estas linhas no fim do arquivo:

   ```hcl
   terraform {
     cloud {}
   }
   ```

3. Garanta que o **bloco `backend "s3"` continua comentado** (só pode haver um).

> *Por que `cloud {}` está vazio?* Porque o nome da organização e do workspace
> vêm de variáveis de ambiente (`TF_CLOUD_ORGANIZATION` e `TF_WORKSPACE`), que o
> Terraform Cloud já injeta sozinho no workspace VCS-driven. Assim não
> escrevemos nomes fixos no código.

4. Salve, faça commit e push:

   ```bash
   git add infra/backend.tf
   git commit -m "infra: ativar Terraform Cloud (bloco cloud)"
   git push
   ```

---

## 6. Passo 4 — ⭐ ONDE COLOCAR AS CREDENCIAIS DO LAB ⭐

**Esta é a parte que você perguntou.** As credenciais **NÃO vão em nenhum
arquivo do repositório** (nunca comite credenciais!). Elas vão no **cofre do
Terraform Cloud**, dentro do workspace.

### 6.1 — Pegue as credenciais no AWS Academy

1. No AWS Academy, clique em **AWS Details** → **AWS CLI** → **Show**.
2. Vai aparecer um bloco assim (são **3** valores):

   ```ini
   aws_access_key_id=ASIA...
   aws_secret_access_key=xxxxxxxx...
   aws_session_token=yyyyyyyy...      <- existe porque é Academy
   ```

### 6.2 — Cole no Terraform Cloud (Workspace → Variables)

1. No Terraform Cloud, abra o workspace `oficina-backend-infra`.
2. Menu lateral: **Variables**.
3. Em **Workspace variables**, clique **+ Add variable** e crie **3 variáveis**,
   todas com **Category = `Environment variable`** (NÃO "Terraform variable")
   e marque **Sensitive** em todas:

   | Key (nome exato)        | Value                         | Category    | Sensitive |
   |-------------------------|-------------------------------|-------------|-----------|
   | `AWS_ACCESS_KEY_ID`     | (o `aws_access_key_id`)        | Environment | ✅        |
   | `AWS_SECRET_ACCESS_KEY` | (o `aws_secret_access_key`)    | Environment | ✅        |
   | `AWS_SESSION_TOKEN`     | (o `aws_session_token`)        | Environment | ✅        |

> **Por que "Environment variable" e não "Terraform variable"?**
> O provider da AWS lê as credenciais das variáveis de ambiente do sistema
> (`AWS_ACCESS_KEY_ID` etc.). Marcar como *Environment* faz o Terraform Cloud
> exportar esses valores no ambiente onde ele roda o `apply`, exatamente como se
> você tivesse colocado no `~/.aws/credentials`.

> 🔁 **Toda vez que abrir um novo lab do Academy:** volte nesta tela e
> **atualize os 3 valores** (as credenciais antigas expiram). É o único passo
> manual que sobra.

### 6.3 — Variáveis da aplicação (Terraform variables)

Ainda em **Variables**, adicione as variáveis do nosso Terraform como
**Category = `Terraform variable`** (estas NÃO são segredo, exceto a senha):

| Key                     | Value (exemplo)                                   | Sensitive |
|-------------------------|---------------------------------------------------|-----------|
| `aws_region`            | `us-west-2`                                       | não       |
| `lab_role_arn`          | `arn:aws:iam::SEU_ACCOUNT_ID:role/LabRole`        | não       |
| `db_password`           | (uma senha forte que VOCÊ escolher)               | ✅        |
| `db_engine_version`     | `16`                                              | não       |

> Para descobrir o `SEU_ACCOUNT_ID`, rode no lab:
> `aws sts get-caller-identity --query Account --output text`
> ⚠️ **No Academy o Account ID pode mudar entre labs** — confira no começo de
> cada sessão e ajuste o ARN de `lab_role_arn`.

> ⭐ **Não crie a variável `access_entry_role_arn` no Academy (deixe sem definir).**
> A role **`voclabs`** (a que você assume) tem um **deny explícito** (policy
> `voc-cancel-cred`) em `eks:CreateAccessEntry`, então se você apontar essa
> variável pra `voclabs` o **apply falha** com `AccessDenied`. O acesso admin do
> `kubectl` vem do **`bootstrap_cluster_creator_admin_permissions = true`** já
> configurado no `infra/eks-cluster.tf`: o EKS concede admin a quem **cria** o
> cluster (a `voclabs` usada pelo Terraform Cloud), e o `kubectl` funciona logo
> após o `update-kubeconfig`, sem nenhum passo manual de Access Entry. Em conta
> AWS normal, aí sim você pode preencher `access_entry_role_arn` com seu IAM.

> *E o `create_state_backend`?* O default no código já é **`false`** (Academy não
> cria S3/DynamoDB, e o state fica no Terraform Cloud). Só adicione essa variável
> como `true` se estiver numa conta AWS normal e quiser o backend S3+DynamoDB.

> ℹ️ Não é mais necessário criar a variável `availability_zones`: o default do
> código já é `["us-west-2a", "us-west-2b"]`.

---

## 7. Passo 5 — Rodar a infra (o momento da automação)

Com tudo configurado, há duas formas de disparar:

### Forma A (recomendada) — pelo próprio Terraform Cloud (VCS)
1. Faça qualquer `git push` que toque em `infra/` (o push do Passo 3 já serve).
2. No Terraform Cloud, abra o workspace → aba **Runs**. Vai haver um run
   **"Planning"** em andamento.
3. Quando terminar o **plan**, revise o que será criado (VPC, EKS, RDS…).
4. Clique em **Confirm & Apply** → escreva um comentário → **Confirm Plan**.
5. Acompanhe o **apply** (leva ~15–20 min: EKS e RDS são lentos).

### Forma B (opcional) — pelo GitHub Actions
Já deixamos pronto o workflow `.github/workflows/infra.yml`. Para usá-lo:
1. Crie um **token** no Terraform Cloud: ícone do usuário → **User Settings** →
   **Tokens** → **Create an API token**. Copie o valor.
2. No GitHub: repositório → **Settings** → **Secrets and variables** →
   **Actions** → **New repository secret**:
   - **Name:** `TF_API_TOKEN`
   - **Secret:** (cole o token do Terraform Cloud)
3. Edite `.github/workflows/infra.yml` e troque `SUA_ORGANIZACAO_AQUI` pelo nome
   da sua organização.
4. No GitHub: aba **Actions** → workflow **"Infra (Terraform Cloud)"** →
   **Run workflow** → escolha `plan` (ou `apply`).

> As duas formas usam o **mesmo** workspace e as **mesmas** credenciais (do
> Passo 4). A Forma A é mais simples; a Forma B é útil se você quiser tudo
> dentro do GitHub.

---

## 8. Passo 6 — Conectar o kubectl e subir a aplicação

A infra (cluster) está pronta, mas a **aplicação** ainda precisa ser instalada
no cluster. Isso continua sendo feito com `kubectl` (ou pela esteira `cd.yml`).

### 8.1 — ⭐ Exportar as credenciais do lab no SEU terminal (a cada sessão)

O `aws` e o `kubectl` rodam **na sua máquina**, então eles precisam das credenciais
do lab no terminal. Atualizar as credenciais no Terraform Cloud (Passo 4.2) serve
só pro TFC — **não** vale pro seu PowerShell. Antes de rodar qualquer `aws`/`kubectl`,
cole os 3 valores do lab (**AWS Details → AWS CLI → Show**) no PowerShell:

```powershell
$env:AWS_ACCESS_KEY_ID="ASIA...."
$env:AWS_SECRET_ACCESS_KEY="...."
$env:AWS_SESSION_TOKEN="...."
$env:AWS_DEFAULT_REGION="us-west-2"
```

Confirme que valeram (tem que mostrar a conta/role `voclabs`, sem erro):
```powershell
aws sts get-caller-identity
```

> 💡 **Atalho pra não ficar colando 3 linhas:** copie o bloco inteiro do **AWS CLI**
> no Academy (o botão de copiar) e rode o helper — ele lê da área de transferência,
> configura as 3 variáveis e já valida:
> ```powershell
> ./k8s/set-aws-creds.ps1
> ```

> 🔁 **Por que toda sessão?** As credenciais do AWS Academy são **temporárias** e
> **expiram quando o lab para/encerra** (o lab anexa um deny `voc-cancel-cred` e os
> comandos passam a dar `AccessDenied`/`security token is invalid`). Isso é uma
> limitação do Academy — **não tem como evitar** o refresh a cada sessão. Em conta
> AWS normal você configuraria uma vez (`aws configure`) e pronto. O helper acima é
> o jeito mais rápido de refazer isso quando reabrir o lab.

### 8.2 — Conectar o kubectl

```bash
aws eks update-kubeconfig --region us-west-2 --name oficina-dev
kubectl get nodes   # tem que listar os 2 nós Ready
```

> Se o `kubectl` der `the server has asked for the client to provide credentials`,
> veja a seção **Problemas comuns** — no Academy o acesso vem do
> `bootstrap_cluster_creator_admin_permissions` (cluster criado pela `voclabs` do
> TFC); a `voclabs` não pode conceder acesso via Access Entry.

### 8.3 — Subir a app apontando pro RDS (recomendado no Academy)

> ⚠️ **Não use `kubectl apply -f k8s/` cru no Academy.** Aquele diretório sobe um
> **Postgres dentro do cluster** (`postgres-*.yaml`) que depende do driver **EBS
> CSI** — e o EBS CSI precisa de **IRSA** (role via OIDC), que o Academy bloqueia.
> Resultado: o PVC fica `Pending` e a app entra em `CrashLoopBackOff`.
> A arquitetura da Fase 2 usa o **RDS** (criado pelo Terraform) — use o script
> abaixo, que aponta a app pro RDS e **não** sobe o Postgres no cluster.

**PowerShell (Windows):**
```powershell
# passe a MESMA senha que você usou na variável db_password do Terraform
./k8s/deploy-aws-academy.ps1 -DbPassword "<sua-senha-do-rds>"
```

**Bash (terminal do lab):**
```bash
DB_PASSWORD="<sua-senha-do-rds>" ./k8s/deploy-aws-academy.sh
```

> 🔐 Use a **mesma** senha que você definiu na variável `db_password` do Terraform.
> Para produção, passe também um `JWT_SECRET`/`ADMIN_PASSWORD` próprios (parâmetros
> `-JwtSecret`/`-AdminPassword` no PowerShell ou variáveis de ambiente no bash).
> Se você não informar o `JWT_SECRET`, o script **gera um valor aleatório forte**
> automaticamente; o `ADMIN_PASSWORD`, se omitido, usa um default de
> **desenvolvimento** (`admin123`) com aviso.

O script descobre o endpoint do RDS sozinho (evita o bug de host vazio), cria o
ConfigMap/Secret corretos e sobe Deployment + Service + HPA.

Depois pegue o endereço do LoadBalancer e acesse o Swagger:

```bash
kubectl get pods -n oficina -w           # espere 1/1 Running
kubectl get svc oficina-app -n oficina   # pegue o EXTERNAL-IP (ELB, ~2-4 min)
# acesse http://<EXTERNAL-IP>/swagger-ui/index.html
```

> **HPA / autoscaling no Academy:** o HPA já vem configurado (`k8s/hpa.yaml`,
> 2→5 réplicas a 70% CPU). Porém o `metrics-server` **não funciona no Academy**:
> o EKS não emite o certificado de *serving* do kubelet (os CSRs
> `kubelet-serving` ficam `Approved` mas nunca `Issued`), então `kubectl top` e o
> HPA não leem CPU. É limitação do ambiente, não do projeto. Para demonstrar o
> escalonamento ao vivo, use `kubectl scale deployment oficina-app -n oficina
> --replicas=4` (e volte pra 2). Em conta AWS normal o HPA escala sozinho.

> *Terraform Cloud cria a INFRA; quem instala a APP é o kubectl / GitHub Actions
> (cd.yml). São papéis diferentes.*

---

## 9. Passo 7 — Destruir a infra (economizar crédito do lab)

Quando terminar o teste, **destrua tudo** para não gastar crédito. A **ordem
importa** — pular o passo 1 faz o destroy travar no meio (foi um dos pontos que nos
atrasou).

### 9.1 — ANTES de destruir: apagar o LoadBalancer (libera o ELB)

O endereço público (ELB) é criado **pelo Kubernetes**, não pelo Terraform. Se você
mandar destruir sem apagá-lo, ele fica **órfão segurando a VPC/subnet** e o
`terraform destroy` falha. Apague o Service e espere o ELB sumir:

```powershell
kubectl delete svc oficina-app -n oficina
# espere ~1-2 min e confirme que sumiu (tem que voltar vazio):
aws elb describe-load-balancers --region us-west-2 --query "LoadBalancerDescriptions[].DNSName" --output text
```

### 9.2 — Reatualizar as 3 credenciais no Terraform Cloud

O destroy roda no Terraform Cloud, então as credenciais lá precisam estar
**válidas**. Se o lab ficou aberto muito tempo, refaça o **Passo 4.2** (cole os 3
valores atuais do AWS CLI). Senão o destroy falha com *"No valid credential
sources found"*.

### 9.3 — Disparar o destroy

1. Workspace → menu lateral **Settings** → **Destruction and Deletion**.
2. Clique em **Queue destroy plan**.
3. ⚠️ Vai aparecer um campo de confirmação pedindo para digitar **`delete`**
   (a palavra `delete`, literalmente — **não** o nome do workspace). Digite
   `delete` e o botão habilita.
4. Abre um run de destruição. Quando o **plan** terminar (lista ~23 recursos para
   *destroy*), clique **Confirm & Apply** → escreva um comentário → confirme.
5. ⏳ Leva ~10-15 min (EKS e RDS demoram para apagar). No fim deve aparecer:
   `Apply complete! Resources: 0 added, 0 changed, 23 destroyed`.

> Alternativa: **Actions** → **Start new run** → marque **Destroy mode** → **Start**.

### 9.4 — Encerrar o lab

Depois do destroy concluído, vá no AWS Academy e clique **End Lab**. Aí o custo
para de vez.

> 💡 Conferência opcional (tudo deve voltar **vazio**):
> ```powershell
> aws eks list-clusters --region us-west-2
> aws rds describe-db-instances --region us-west-2 --query "DBInstances[].DBInstanceIdentifier"
> aws elb describe-load-balancers --region us-west-2 --query "LoadBalancerDescriptions[].DNSName"
> ```

> ⚠️ Faça o destroy **enquanto o lab ainda está ativo** (as credenciais precisam
> estar válidas). Se o lab expirar antes, reabra, refaça o Passo 4.2 e só então
> destrua.

---

## 10. Resumo — o que mudou em relação ao Runbook manual

| Etapa                         | Antes (Runbook manual)              | Agora (Terraform Cloud)                         |
|-------------------------------|-------------------------------------|-------------------------------------------------|
| Onde rodam plan/apply         | Terminal do lab, na mão             | Nuvem da HashiCorp, via push/clique             |
| Onde fica o state             | Arquivo local `terraform.tfstate`   | Cofre do Terraform Cloud (não se perde)         |
| Onde ficam as credenciais AWS | `~/.aws/credentials` no lab         | Workspace → Variables (Environment, Sensitive)  |
| Disparo                       | Você digita os comandos             | `git push` (ou botão no GitHub Actions)         |
| O que ainda é manual          | Tudo                                | Só atualizar as 3 credenciais a cada novo lab   |
| Instalar a aplicação (k8s)    | `kubectl apply`                     | `kubectl apply` ou esteira `cd.yml` (igual)     |

---

## 11. Problemas comuns

- **"Error: No valid credential sources found" no apply:** as credenciais do lab
  expiraram. Volte ao **Passo 4.2** e atualize os 3 valores no workspace.
- **`UnauthorizedOperation` / `AccessDenied`:** você está numa região não
  liberada. No Academy use **`us-west-2`** (variable `aws_region`).
- **`Error: Required token could not be found` (GitHub Actions):** falta o secret
  `TF_API_TOKEN` no GitHub (Passo 5, Forma B).
- **Plan não dispara após o push:** confira no workspace → **Settings** →
  **Version Control** se o **Working Directory** está como `infra`.
- **`iam:CreateRole` negado:** o `lab_role_arn` não foi preenchido — sem ele o
  Terraform tenta criar IAM roles (proibido no Academy). Preencha no Passo 6.3.
- **`InvalidParameterValue: us-east-1a ... invalid` no apply:** os defaults de
  `aws_region`/`availability_zones` estão desalinhados. Já corrigido no código
  (defaults `us-west-2`); se persistir, confira a variável `aws_region` = `us-west-2`.
- **`kubectl`: "the server has asked for the client to provide credentials":** o
  seu principal (`voclabs`) não tem acesso ao cluster. O código já resolve isso
  com **`bootstrap_cluster_creator_admin_permissions = true`** no `access_config`
  (`infra/eks-cluster.tf`): o EKS concede admin automaticamente a quem **cria** o
  cluster (a `voclabs` usada pelo Terraform Cloud), sem usar `eks:CreateAccessEntry`.
  - ⚠️ **Não tente criar a Access Entry na mão no Academy:** a role `voclabs` tem um
    **deny explícito** (policy `voc-cancel-cred`) em `eks:CreateAccessEntry`/
    `AssociateAccessPolicy`/`ListAccessEntries`, então os comandos
    `aws eks create-access-entry`/`associate-access-policy` retornam `AccessDenied`.
  - Se o cluster foi criado **antes** dessa configuração, ele precisa ser
    **recriado** (o `bootstrap_*` só vale no momento da criação). Garanta que as
    credenciais do Terraform Cloud são as da **sessão atual** (Passo 4.2), que
    `access_entry_role_arn` está **vazio** (a `voclabs` não consegue criar a entry),
    e rode o apply de novo.
- **App em `CrashLoopBackOff` (probe `:8080 connection refused`):** a app não
  conecta no banco no boot. Causas comuns:
  - **DB_URL com host vazio** (`jdbc:postgresql:///oficina`): no PowerShell,
    `$RDS:5432` é interpretado errado por causa do `:` — use `${RDS}:5432` (com
    chaves) ou rode o `deploy-aws-academy.ps1`, que já trata isso.
  - **Senha divergente:** o `DB_PASSWORD` do Secret precisa ser igual à
    `db_password` do Terraform (senha master do RDS).
  - Confira: `kubectl get cm oficina-config -n oficina -o jsonpath="{.data.DB_URL}"`.
- **Pods do `oficina-db` em `Pending` / EBS CSI `CrashLoopBackOff`:** EBS CSI
  precisa de IRSA (bloqueado no Academy). Não use o Postgres no cluster — use o
  RDS via `deploy-aws-academy.ps1` (não aplique `k8s/postgres-*.yaml`).
- **`kubectl logs/top`: `tls: internal error` e HPA `cpu: <unknown>`:** o EKS do
  Academy não emite o cert de serving do kubelet. Sem solução simples no lab;
  para o vídeo, demonstre escalonamento com `kubectl scale`.
- **`configmap/oficina-config unchanged` e o `DB_URL` continua `///` (host vazio):**
  é o bug do PowerShell — `$RDS:5432` (com `:` colado) vira vazio, então o YAML
  fica igual ao anterior e o `apply` diz "unchanged". Use `${RDS}:5432` (com
  chaves) ou, mais simples, rode o `deploy-aws-academy.ps1` que já trata isso.
- **Tela de destroy não avança / botão desabilitado:** o campo pede a palavra
  **`delete`** (literal), não o nome do workspace. Digite `delete` (Passo 9.3).
- **Destroy falha em VPC/subnet com "DependencyViolation" ou "has dependencies":**
  sobrou um recurso criado fora do Terraform segurando a rede — quase sempre o
  **ELB do Service** (apague com `kubectl delete svc oficina-app -n oficina`,
  Passo 9.1) e rode o destroy de novo.
- **`Start Lab` esquecido:** se os comandos `aws ...` devolvem erro de credencial
  logo de cara, confirme que o lab está com a bolinha **verde** (Start Lab feito)
  e que você reatualizou os 3 valores no Passo 4.2.

---

## 12. Apêndice — Sequência completa do dia (copiar e colar)

Roteiro fim-a-fim já com a ordem certa. Substitua `<sua-senha-do-rds>` pela senha
que você pôs na variável `db_password` do workspace.

```powershell
# 0) (no AWS Academy) Start Lab -> AWS Details -> AWS CLI -> Show (copie os 3 valores)
#    e cole-os nos 3 Environment variables do workspace (Terraform Cloud).

# 1) Conferir conta e região (ajuste os ARNs no workspace se o Account ID mudou)
aws sts get-caller-identity

# 2) (Terraform Cloud) Actions -> Start new run -> Confirm & Apply  [~15-20 min]
#    Espere "Apply complete! Resources: 23 added".

# 3) Conectar o kubectl ao cluster
aws eks update-kubeconfig --region us-west-2 --name oficina-dev
kubectl get nodes                          # 2 nós Ready

# 4) Subir a aplicação apontando pro RDS (NÃO use kubectl apply -f k8s/)
./k8s/deploy-aws-academy.ps1 -DbPassword "<sua-senha-do-rds>"

# 5) Acompanhar e pegar a URL pública
kubectl get pods -n oficina -w             # espere oficina-app 1/1 Running (Ctrl+C p/ sair)
kubectl get svc oficina-app -n oficina     # copie o EXTERNAL-IP (ELB, ~2-4 min)
curl.exe http://<ELB>/actuator/health      # esperado: {"status":"UP"}
# navegador: http://<ELB>/swagger-ui/index.html

# 6) (opcional, p/ o vídeo) demonstrar escalonamento manual
kubectl get hpa -n oficina
kubectl scale deployment oficina-app -n oficina --replicas=4
kubectl get pods -n oficina                # 4 pods
kubectl scale deployment oficina-app -n oficina --replicas=2

# 7) DESTRUIR (na ordem!) para zerar custo
kubectl delete svc oficina-app -n oficina  # libera o ELB ANTES do destroy
#    (Terraform Cloud) Settings -> Destruction and Deletion -> digite "delete"
#    -> Queue destroy plan -> Confirm & Apply  [~10-15 min, "23 destroyed"]
#    (AWS Academy) End Lab
```
