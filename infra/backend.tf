# ─── Onde fica o "state" do Terraform ───
#
# O Terraform guarda um arquivo de "state" (o mapa de tudo que ele criou na AWS).
# Existem 3 jeitos de guardar esse state. Escolha UM descomentando o bloco certo:
#
#   (1) LOCAL  -> nenhum bloco abaixo. O state fica no arquivo terraform.tfstate
#                 na sua máquina. É o que usamos no AWS Academy manual (Runbook).
#
#   (2) S3     -> bloco "backend s3" (modelo da Aula 8). Exige criar um bucket
#                 antes (bucket.tf). No AWS Academy a role voclabs NÃO pode criar
#                 bucket/DynamoDB, então normalmente NÃO usamos.
#
#   (3) TERRAFORM CLOUD (HCP Terraform)  -> bloco "cloud" abaixo. É a AUTOMAÇÃO:
#                 o state fica na nuvem da HashiCorp e os plan/apply rodam lá,
#                 disparados por push no GitHub. É o que o
#                 GUIA-TERRAFORM-CLOUD-AWS-ACADEMY.md ensina a configurar.
#
# Só pode existir UM bloco de backend/cloud ativo por vez.

# ── (2) Backend remoto S3 (modelo da aula) — manter COMENTADO no Academy ──
# terraform {
#   backend "s3" {
#     bucket         = "oficina-terraform-state-CHANGE_ME"
#     key            = "oficina-backend/terraform.tfstate"
#     region         = "us-west-2"
#     dynamodb_table = "oficina-terraform-locks"
#     encrypt        = true
#   }
# }

# ── (3) Terraform Cloud (HCP Terraform) — descomente para usar a automação ──
#
# A organização e o workspace são lidos das variáveis de ambiente
# TF_CLOUD_ORGANIZATION e TF_WORKSPACE (definidas no GitHub Actions e/ou no
# seu terminal), então NÃO precisamos escrever nomes fixos aqui.
#
# Passo a passo completo: GUIA-TERRAFORM-CLOUD-AWS-ACADEMY.md
#
# Ativar terraform
# Ativar terraform (2)
# Ativar terraform (3)
#
terraform {
  cloud {}
}
