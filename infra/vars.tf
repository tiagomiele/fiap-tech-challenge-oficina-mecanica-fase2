variable "aws_region" {
  description = "Região AWS para provisionar os recursos"
  type        = string
  default     = "us-west-2"
}

variable "environment" {
  description = "Ambiente (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Nome do projeto (usado como prefixo nos recursos)"
  type        = string
  default     = "oficina"
}

# ---------- State remoto (backend.tf / bucket.tf) ----------

variable "state_bucket_name" {
  description = "Nome GLOBALMENTE único do bucket S3 que guarda o state do Terraform"
  type        = string
  default     = "oficina-terraform-state-change-me"
}

variable "state_lock_table_name" {
  description = "Nome da tabela DynamoDB usada para lock do state"
  type        = string
  default     = "oficina-terraform-locks"
}

# ---------- Rede ----------

variable "vpc_cidr" {
  description = "CIDR block da VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Zonas de disponibilidade"
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b"]
}

# ---------- EKS ----------

variable "cluster_version" {
  description = "Versão do Kubernetes no EKS"
  type        = string
  default     = "1.31"
}

variable "node_instance_type" {
  description = "Tipo de instância EC2 para os worker nodes"
  type        = string
  default     = "t3.medium"
}

variable "node_desired_count" {
  description = "Número desejado de worker nodes"
  type        = number
  default     = 2
}

variable "node_min_count" {
  description = "Número mínimo de worker nodes"
  type        = number
  default     = 2
}

variable "node_max_count" {
  description = "Número máximo de worker nodes"
  type        = number
  default     = 5
}

# ---------- RDS ----------

variable "db_instance_class" {
  description = "Classe da instância RDS"
  type        = string
  default     = "db.t3.micro"
}

variable "db_name" {
  description = "Nome do banco de dados"
  type        = string
  default     = "oficina"
}

variable "db_username" {
  description = "Usuário master do RDS"
  type        = string
  default     = "oficina"
}

variable "db_password" {
  description = "Senha do banco de dados"
  type        = string
  sensitive   = true
}

variable "db_allocated_storage" {
  description = "Armazenamento alocado em GB"
  type        = number
  default     = 20
}

variable "create_state_backend" {
  description = "Cria o bucket S3 + tabela DynamoDB para state remoto. Em AWS Academy a role voclabs costuma NÃO ter s3:CreateBucket/dynamodb:CreateTable, então o default é false (state fica no Terraform Cloud). Em conta AWS normal, defina true se quiser criar o backend S3+DynamoDB."
  type        = bool
  default     = false
}

variable "db_engine_version" {
  description = "Versão do engine PostgreSQL do RDS. Use uma versão fixa (ex.: \"16\" ou \"16.4\") — no AWS Academy a LabRole não tem permissão para descobrir a versão dinamicamente (rds:DescribeDBEngineVersions)."
  type        = string
  default     = "16"
}

# ---------- AWS Academy (Learner Lab) ----------

variable "lab_role_arn" {
  description = "ARN de uma IAM role pré-existente para reutilizar (ex.: LabRole no AWS Academy, onde criar roles é bloqueado). Deixe vazio em conta AWS normal para o Terraform criar as roles."
  type        = string
  default     = ""
}

# ---------- Controle de acesso ao cluster (EKS Access Entry) ----------

variable "access_entry_role_arn" {
  description = "ARN de um IAM role/usuário que receberá acesso admin ao cluster via Access Entry (ex.: a LabRole ou seu usuário). Vazio = não cria Access Entry."
  type        = string
  default     = ""
}
