# 🚀 Runbook — Deploy da Oficina Backend na AWS Academy (EKS + RDS)

> **Objetivo:** subir a aplicação na AWS do zero, **copiando e colando** os comandos na ordem.
> Testado no **AWS Academy Learner Lab** (região `us-west-2`). Tempo total: ~30-40 min (a maior parte é espera do EKS/RDS).
>
> ✅ Todos os ajustes que precisamos descobrir "na mão" já estão **versionados no Terraform** (versão do K8s, regra de security group, versão do Postgres, liberação da cluster-SG no RDS). Então este runbook é o **caminho feliz**: é só seguir.

---

## 📋 Pré-requisitos (só na 1ª vez)

Você vai usar o **terminal Linux do Learner Lab** (onde as credenciais AWS já vêm carregadas). Instale `terraform`, `kubectl` e o `aws-cli v2` **no seu home** (sem `sudo`).

```bash
# diretório pra binários locais
mkdir -p ~/bin && export PATH="$HOME/bin:$PATH"
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc

# 1) AWS CLI v2 (o v1 do lab gera kubeconfig velho que o kubectl rejeita!)
cd ~
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
unzip -q -o awscliv2.zip        # demora ~1 min extraindo, é normal
./aws/install -i ~/aws-cli -b ~/bin --update
hash -r

# 2) kubectl 1.31
curl -fsSLO "https://dl.k8s.io/release/v1.31.0/bin/linux/amd64/kubectl"
chmod +x kubectl && mv kubectl ~/bin/

# 3) terraform (se ainda não tiver)
curl -fsSLO "https://releases.hashicorp.com/terraform/1.9.5/terraform_1.9.5_linux_amd64.zip"
unzip -q -o terraform_1.9.5_linux_amd64.zip && mv terraform ~/bin/

# conferir versões (aws DEVE ser 2.x)
aws --version
kubectl version --client
terraform version
```

> 💡 O aviso `Starlark failed to allocate 4GB...` que aparece no `kubectl` é **ruído do ambiente do lab** e pode ser **ignorado** sempre.

---

## 🔑 Passo 0 — clonar o repo e checar credenciais

### 0.1 — Gerar o token do GitHub (o repo é **privado**)

O GitHub **não aceita mais senha** no `git clone` — você precisa de um **Personal Access Token (PAT)**. Caminho para pegar o token real:

1. Acesse: **https://github.com/settings/tokens/new**
   (ou pelo menu: foto do perfil → **Settings** → **Developer settings** → **Personal access tokens** → **Tokens (classic)** → **Generate new token (classic)**)
2. **Note**: `lab-clone`
3. **Expiration**: `7 days` (ou o que preferir)
4. **Select scopes**: marque a caixa **`repo`** (a primeira — cobre repositórios privados)
5. Role até o fim e clique em **Generate token**
6. **Copie o token** (começa com `ghp_...`) — ele **só aparece uma vez**. Guarde num lugar seguro.

> ⚠️ **Nunca** cole o token em chat, commit ou documentação. Se vazar, revogue em https://github.com/settings/tokens (**Delete**) e gere outro.

### 0.2 — Clonar com o token

Embuta o token na URL (troque `ghp_SEU_TOKEN` pelo seu):
```bash
cd ~
git clone https://tiagomiele:ghp_SEU_TOKEN@github.com/tiagomiele/fiap-tech-challenge-oficina-mecanica-fase2.git
cd fiap-tech-challenge-oficina-mecanica-fase2
```

Agora **garanta que você está no código com os fixes** (LabRole, k8s 1.31, regra de SG) — escolha **um** caso:

- **Se o PR de consolidação JÁ foi mergeado na `main`:**
  ```bash
  git checkout main && git pull
  ```
- **Se o PR ainda está ABERTO** (não mergeado), use a branch consolidada direto:
  ```bash
  git checkout main
  ```

> 🛑 **Confirme antes de seguir** (causa de erro silencioso): se você ficar na `main` **sem os fixes**, o `terraform apply` tenta **criar IAM roles** (403) e usa a regra de SG antiga. Verifique:
> ```bash
> git rev-parse --abbrev-ref HEAD                                   # branch atual
> grep -n 'count = local.use_lab_role' infra/modules/eks/main.tf    # TEM que achar (linha ~17/88)
> ```
> Se o `grep` **não achar nada**, você está no código antigo — faça o `git checkout` da branch/`main` correta antes de continuar.

**Erros comuns nesta etapa:**
- `Password authentication is not supported` → o que você colou na senha **não é um PAT válido** (era a senha da conta, token expirado, ou sem o escopo `repo`). Gere um novo seguindo o 0.1.
- `destination path '...' already exists and is not an empty directory` → a pasta já existe. Use o que já está lá (`cd fiap-tech-challenge-oficina-mecanica-fase2 && git pull`) **ou** apague: `cd ~ && rm -rf fiap-tech-challenge-oficina-mecanica-fase2` e clone de novo.
- `Stale file handle` ao apagar/clonar → você está **dentro** da pasta que tentou apagar. Saia antes: `cd ~` e só então rode o `rm -rf`/`git clone`.

### 0.3 — Checar credenciais da AWS

```bash
# confirma que as credenciais do lab estão ativas
aws sts get-caller-identity
```
A saída deve mostrar a conta `163061816974` e a `LabRole`. Se der erro de credencial, **clique em "AWS Details → Show" no lab e copie as credenciais** pro terminal (ou apenas use o terminal já autenticado do lab).

---

## 🏗️ Passo 1 — provisionar a infra (Terraform)

Para o AWS Academy, use o exemplo **`terraform.tfvars.academy.example`** (já vem com `us-west-2`, `cluster_version = 1.31` e a estrutura da LabRole). O exemplo "comum" (`terraform.tfvars.example`) é para conta AWS normal — não use no lab.

```bash
cd ~/fiap-tech-challenge-oficina-mecanica-fase2/infra

# cria o terraform.tfvars a partir do exemplo do AWS Academy
cp terraform.tfvars.academy.example terraform.tfvars
```

### O que você precisa preencher (e de onde tirar o valor)

| Campo no `terraform.tfvars` | O que é / o que colocar | De onde pegar o valor |
|---|---|---|
| `lab_role_arn` | ARN da **LabRole** da sua conta (vem como `arn:aws:iam::ACCOUNT_ID:role/LabRole` — você troca o `ACCOUNT_ID` pelo número da SUA conta) | Rode no terminal do lab: `aws iam get-role --role-name LabRole --query 'Role.Arn' --output text` |
| `db_password` | A senha que o RDS vai usar (vem como `ALTERAR_PARA_SENHA_SEGURA`) | **Você escolhe.** Anote — vai precisar dela no Passo 3 (secret) e pra acessar o banco. Ex.: `OficinaFase2!2026A` |

> 💡 As credenciais do lab **mudam a cada vez que você inicia o Learner Lab**, mas o **número da conta** e o **ARN da LabRole** costumam ser os mesmos. Ainda assim, **sempre** pegue o ARN com o comando acima — é a fonte da verdade desta execução.

Cole este bloco que **preenche os dois campos automaticamente** (pega o ARN da sua conta e define a senha):

```bash
# 1) descobre o ARN da LabRole DESTA conta e injeta no tfvars
LAB_ROLE_ARN=$(aws iam get-role --role-name LabRole --query 'Role.Arn' --output text)
echo "LabRole desta conta: $LAB_ROLE_ARN"   # NÃO pode vir vazio
sed -i "s#arn:aws:iam::ACCOUNT_ID:role/LabRole#${LAB_ROLE_ARN}#" terraform.tfvars

# 2) define a senha do banco (troque pela que quiser; anote-a!)
sed -i 's/ALTERAR_PARA_SENHA_SEGURA/OficinaFase2!2026A/' terraform.tfvars

# 3) confere que os dois ficaram preenchidos (sem ACCOUNT_ID e sem ALTERAR_...)
grep -E 'lab_role_arn|db_password' terraform.tfvars
```

> 🛑 **AWS Academy — atenção (causa de erro #1):** a linha `lab_role_arn` é **obrigatória** e tem que apontar pra LabRole da **sua** conta. No Learner Lab você **não tem permissão para criar IAM roles**; sem essa linha (ou com o `ACCOUNT_ID` não substituído) o `terraform apply` quebra com `AccessDenied ... iam:CreateRole`. Confirme antes do apply:
> ```bash
> grep lab_role_arn terraform.tfvars   # NÃO pode conter "ACCOUNT_ID"
> aws sts get-caller-identity --query Account --output text   # deve bater com o nº da conta no ARN acima
> ```

Provisione:
```bash
terraform init
terraform plan -out=tfplan
```

> 🛑 **Confira a região no resumo do `plan` ANTES de aplicar (causa de recursos órfãos):** o plano tem que mostrar `us-west-2` e **nenhuma** criação de `aws_iam_role.cluster`/`aws_iam_role.node`. Se você já tinha rodado um apply numa região diferente (ex.: `us-east-1`, do `terraform.tfvars.example` genérico), trocar de região **abandona** os recursos antigos no *state* — eles viram **órfãos** (principalmente o **NAT gateway**, que custa crédito) e o `terraform destroy` do fim **não** os remove. Veja como limpar na seção de Troubleshooting.

```bash
terraform apply tfplan      # digite 'yes' se pedir confirmação
```

⏱️ **Demora ~20 min** (EKS ~10 min + node group ~3 min + RDS ~7 min). É normal ficar mostrando `Still creating...`.

No fim aparece **`Apply complete!`** e os **Outputs**. **Anote o `rds_endpoint`** (ex.: `oficina-dev-db.xxxx.us-west-2.rds.amazonaws.com:5432`) — você vai usar no Passo 3.

```bash
# guarda os outputs em variáveis pra reaproveitar
RDS_HOST=$(terraform output -raw rds_endpoint | cut -d: -f1)
echo "RDS_HOST=$RDS_HOST"
```

---

## 🔌 Passo 2 — conectar o kubectl ao cluster

```bash
aws eks update-kubeconfig --region us-west-2 --name oficina-dev
kubectl get nodes
```
Deve listar **2 nós** com status `Ready` (pode levar ~1 min).

> ⚠️ Se aparecer `invalid apiVersion "client.authentication.k8s.io/v1alpha1"`, é porque o kubeconfig foi gerado pelo AWS CLI **v1**. Garanta que o `aws --version` mostra **2.x** e rode de novo o `update-kubeconfig`. (Se ainda persistir: `sed -i 's#v1alpha1#v1beta1#' "$HOME/.kube/config"`.)

---

## 🐳 Passo 3 — publicar a aplicação no EKS

### 3.1 — imagem do GHCR pública (só na 1ª vez)
A imagem precisa estar **pública** pro EKS baixar sem credencial. Confira/ajuste em:
👉 https://github.com/users/tiagomiele/packages/container/fiap-tech-challenge-oficina-mecanica-fase2/settings
→ **Danger Zone → Change visibility → Public**. (Libera só a imagem Docker, não o repositório.)

### 3.2 — ajustar os manifestos pro RDS

> 🛑 **Atenção (causa de erro #3):** o **endpoint do RDS muda a cada `terraform apply`** (a AWS gera um trecho aleatório no hostname). Por isso o `DB_URL` do configmap **tem que ser setado a partir do `terraform output`**, nunca digitado/hardcoded. Se o `DB_URL` ficar errado (ou vazio), o app cai no default `localhost` e os pods entram em `CrashLoopBackOff` com `Connection to localhost:5432 refused`.

```bash
cd ~/fiap-tech-challenge-oficina-mecanica-fase2

# (re)descobre o endpoint do RDS DESTE apply — rode sempre, mesmo em sessão nova
RDS_HOST=$(cd infra && terraform output -raw rds_endpoint | cut -d: -f1)
echo "RDS_HOST=$RDS_HOST"   # NÃO pode vir vazio

# aponta o app pro endpoint do RDS deste apply
sed -i "s#jdbc:postgresql://[^/]*/oficina#jdbc:postgresql://${RDS_HOST}:5432/oficina#" k8s/configmap.yaml

# usa a imagem publicada no GHCR
sed -i 's#image: oficina-backend:latest#image: ghcr.io/tiagomiele/fiap-tech-challenge-oficina-mecanica-fase2:latest#' k8s/app-deployment.yaml
sed -i 's#imagePullPolicy: IfNotPresent#imagePullPolicy: Always#' k8s/app-deployment.yaml

# senha do banco em base64 (= "OficinaFase2!2026A", igual ao terraform.tfvars)
sed -i 's#DB_PASSWORD: ".*"#DB_PASSWORD: "T2ZpY2luYUZhc2UyITIwMjZB"#' k8s/secret.yaml

# conferir
grep DB_URL k8s/configmap.yaml
grep 'image:' k8s/app-deployment.yaml
grep DB_PASSWORD k8s/secret.yaml
```

> 💡 Se mudar a senha do banco, gere o base64 com: `echo -n 'SUA_SENHA' | base64`

### 3.3 — aplicar (NÃO use os manifestos de postgres in-cluster; o banco é o RDS)
```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/secret.yaml
kubectl apply -f k8s/app-deployment.yaml
kubectl apply -f k8s/app-service.yaml

kubectl get pods -n oficina -w   # Ctrl+C quando ficarem 1/1 Running
```
Os pods passam por `ContainerCreating` → `Running` → `1/1`. Leva ~1-2 min.

---

## 🌐 Passo 4 — pegar a URL pública e validar

```bash
EXT=$(kubectl get svc oficina-app -n oficina -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "URL base:  http://$EXT"
echo "Swagger:   http://$EXT/swagger-ui/index.html"

# health check (esperado: {"status":"UP",...})
curl -s "http://$EXT/actuator/health"; echo
# swagger (esperado: HTTP 200)
curl -s -o /dev/null -w "Swagger HTTP %{http_code}\n" "http://$EXT/swagger-ui/index.html"
```

> 🔎 **Como descobrir a URL do Swagger:** é sempre `http://<EXT>/swagger-ui/index.html`, onde `<EXT>` é o hostname do LoadBalancer (o comando acima já monta e imprime a URL pronta). Só existe **um** Swagger — o do serviço rodando no EKS; não há outro para escolher. Abra essa URL no navegador, faça login em `01.01 - Login` (`admin@oficina.local` / `admin123`), clique em **Authorize** 🔒, cole o token e teste os endpoints.
> ⏱️ O LoadBalancer (ELB) leva ~2-3 min pra começar a responder. Se der `timeout`/`Empty reply` na 1ª vez, espere 1 min e repita.

### Smoke test da API (login + criar serviço + listar = grava no RDS)
```bash
TOKEN=$(curl -s -X POST "http://$EXT/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@oficina.local","senha":"admin123"}' \
  | grep -o '"accessToken":"[^"]*"' | cut -d'"' -f4)
echo "TOKEN (tamanho): ${#TOKEN}"

curl -s -X POST "http://$EXT/servicos" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"nome":"Troca de óleo","descricao":"Óleo + filtro","precoBase":150.00}'; echo

curl -s "http://$EXT/servicos" -H "Authorization: Bearer $TOKEN"; echo
```
Esperado: token grande, POST retorna `idServico`, GET lista o serviço criado → **persistiu no RDS** 🎯

### Swagger UI (forma visual)
Abra `http://$EXT/swagger-ui/index.html` → `POST /auth/login` (Try it out) → copie o `accessToken` → botão **Authorize** 🔒 → cole o token → teste os endpoints.

---

## 🗄️ Acessar o banco RDS direto (opcional)

O RDS **não tem IP público** (só os nós do EKS acessam). Pra inspecionar as tabelas, rode um `psql` **de dentro do cluster**:
```bash
kubectl run psql-tmp -n oficina --rm -it --restart=Never --image=postgres:16 -- \
  psql "postgresql://oficina:OficinaFase2!2026A@${RDS_HOST}:5432/oficina"
# dentro do psql:  \dt   (lista tabelas)   |   SELECT * FROM servico;   |   \q  (sair)
```

| Campo | Valor |
|---|---|
| Host | `$RDS_HOST` (output do terraform) |
| Porta | `5432` |
| Banco | `oficina` |
| Usuário | `oficina` |
| Senha | `OficinaFase2!2026A` |

---

## 💸 Passo 5 — DESTRUIR tudo (pra não gastar crédito!)

> **Sempre rode isto ao terminar.** Enquanto EKS/RDS/ELB estiverem de pé, consomem crédito do lab.

```bash
# 1) remove o LoadBalancer (criado pelo k8s, fora do Terraform) — evita ELB órfão
kubectl delete svc oficina-app -n oficina

# 2) derruba toda a infra
cd ~/fiap-tech-challenge-oficina-mecanica-fase2/infra
terraform destroy        # digite 'yes'
```
⏱️ ~10-15 min. No fim: **`Destroy complete!`**

**Checklist final** (tudo deve vir vazio `[]`):
```bash
aws eks list-clusters --region us-west-2
aws rds describe-db-instances --region us-west-2 --query "DBInstances[].DBInstanceIdentifier"
aws elbv2 describe-load-balancers --region us-west-2 --query "LoadBalancers[].LoadBalancerName"
```

---

## 🛠️ Troubleshooting (erros que já enfrentamos e como resolver)

| Sintoma | Causa | Solução |
|---|---|---|
| `AccessDenied: ... iam:CreateRole` | No AWS Academy não se pode criar IAM roles | Defina `lab_role_arn` com a LabRole da sua conta no tfvars — pegue o ARN com `aws iam get-role --role-name LabRole --query 'Role.Arn' --output text` (Passo 1) |
| `unsupported Kubernetes version 1.29` | AWS removeu 1.29 em us-west-2 | Use `cluster_version = "1.31"` (já no tfvars deste runbook) |
| `from_port (0) and to_port (65535) must both be 0 to use 'ALL' "-1"` | Regra de SG com protocolo `-1` exige porta 0 | Já corrigido no `modules/eks/main.tf` |
| `Cannot find version 16.3 for postgres` | Versão de Postgres indisponível na região | Terraform já descobre a versão 16 mais recente automaticamente |
| `kubectl`: `invalid apiVersion ...v1alpha1` | kubeconfig gerado pelo AWS CLI **v1** | Use AWS CLI **v2** e rode `update-kubeconfig` de novo |
| Pods em `CrashLoopBackOff` com `Connection to localhost:5432 refused` (Flyway) | `DB_URL` não aponta pro RDS (configmap não ajustado / `RDS_HOST` vazio) | Refaça o Passo 3.2 derivando `RDS_HOST` do `terraform output`, `kubectl apply -f k8s/configmap.yaml` e `kubectl rollout restart deployment/oficina-app -n oficina` |
| `git clone`: `Password authentication is not supported` | Usou senha da conta em vez de PAT, ou token sem escopo `repo` | Gere um PAT (classic, escopo `repo`) — Passo 0.1 — e use no clone |
| `git clone`: `Stale file handle` | Você está **dentro** da pasta que tentou apagar | `cd ~` antes de `rm -rf`/`git clone` |
| `apply` quebra com `iam:CreateRole` mesmo com `lab_role_arn` setado, e o erro aponta `aws_iam_role.cluster` **sem `[0]`** na linha ~3 | Você está no **código antigo** (branch `main` sem os fixes) | `git checkout` da branch consolidada (ou `main` já mergeada); confirme com `grep 'count = local.use_lab_role' infra/modules/eks/main.tf` (Passo 0.2) |
| Recursos **órfãos** noutra região (ex.: `us-east-1`) após trocar a região do tfvars — `terraform destroy` não os remove | Mudar de região tira os recursos do *state*; eles ficam para trás (NAT gateway gasta crédito) | Apague na mão na região antiga: delete o **NAT gateway** → libere o **Elastic IP** → delete a **VPC** (console: VPC → *Delete VPC*, que remove subnets/IGW/SG/route tables junto). Confira: `aws ec2 describe-nat-gateways --region <REGIAO> --filter Name=state,Values=available` |
| Pods em `CrashLoopBackOff` com `SocketTimeoutException: Connect timed out` (Flyway) | RDS não libera a **cluster security group** do EKS (só a node-SG) | Já corrigido no Terraform (`modules/rds` libera a cluster-SG). Se reaparecer ao vivo: `aws ec2 authorize-security-group-ingress --region us-west-2 --group-id <RDS_SG> --protocol tcp --port 5432 --source-group <CLUSTER_SG>` |
| Pods em `ImagePullBackOff` | Imagem do GHCR ainda **privada** | Torne o pacote **Public** (Passo 3.1) |
| `/actuator/health` dá timeout no 1º acesso | ELB ainda provisionando | Espere ~2-3 min e tente de novo |

---

## 📝 Resumo ultrarrápido (TL;DR)

```bash
# 0. CLONAR (repo privado: use PAT classic com escopo repo — Passo 0.1)
cd ~
git clone https://tiagomiele:ghp_SEU_TOKEN@github.com/tiagomiele/fiap-tech-challenge-oficina-mecanica-fase2.git
cd fiap-tech-challenge-oficina-mecanica-fase2
# se o PR de consolidação já foi mergeado: git checkout main && git pull
# se ainda está aberto:
git checkout main && git pull
# 1. INFRA (AWS Academy: use o exemplo .academy.example)
cd ~/fiap-tech-challenge-oficina-mecanica-fase2/infra
cp terraform.tfvars.academy.example terraform.tfvars   # us-west-2 + k8s 1.31
LAB_ROLE_ARN=$(aws iam get-role --role-name LabRole --query 'Role.Arn' --output text)
sed -i "s#arn:aws:iam::ACCOUNT_ID:role/LabRole#${LAB_ROLE_ARN}#" terraform.tfvars   # injeta a LabRole da sua conta
sed -i 's/ALTERAR_PARA_SENHA_SEGURA/OficinaFase2!2026A/' terraform.tfvars          # define a senha do banco
terraform init && terraform apply -auto-approve
RDS_HOST=$(terraform output -raw rds_endpoint | cut -d: -f1)
# 2. KUBECTL
aws eks update-kubeconfig --region us-west-2 --name oficina-dev
# 3. APP
cd ~/fiap-tech-challenge-oficina-mecanica-fase2
sed -i "s#jdbc:postgresql://[^/]*/oficina#jdbc:postgresql://${RDS_HOST}:5432/oficina#" k8s/configmap.yaml
sed -i 's#image: oficina-backend:latest#image: ghcr.io/tiagomiele/fiap-tech-challenge-oficina-mecanica-fase2:latest#' k8s/app-deployment.yaml
kubectl apply -f k8s/namespace.yaml -f k8s/configmap.yaml -f k8s/secret.yaml -f k8s/app-deployment.yaml -f k8s/app-service.yaml
# 4. VALIDAR
EXT=$(kubectl get svc oficina-app -n oficina -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl -s "http://$EXT/actuator/health"; echo
# 5. DESTRUIR (ao terminar!)
kubectl delete svc oficina-app -n oficina
cd ~/fiap-tech-challenge-oficina-mecanica-fase2/infra && terraform destroy -auto-approve
```
