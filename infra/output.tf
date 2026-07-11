output "vpc_id" {
  description = "ID da VPC criada"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs das subnets públicas"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs das subnets privadas"
  value       = aws_subnet.private[*].id
}

output "eks_cluster_name" {
  description = "Nome do cluster EKS"
  value       = aws_eks_cluster.main.name
}

output "eks_cluster_endpoint" {
  description = "Endpoint do cluster EKS"
  value       = aws_eks_cluster.main.endpoint
}

output "eks_kubeconfig_command" {
  description = "Comando para configurar o kubectl"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.main.name}"
}

output "rds_endpoint" {
  description = "Endpoint de conexão do RDS PostgreSQL"
  value       = aws_db_instance.main.endpoint
}

output "rds_connection_url" {
  description = "URL JDBC para a aplicação"
  value       = "jdbc:postgresql://${aws_db_instance.main.endpoint}/${var.db_name}"
  sensitive   = true
}

output "state_bucket_name" {
  description = "Bucket S3 que guarda o state remoto do Terraform (vazio quando create_state_backend = false)"
  value       = var.create_state_backend ? aws_s3_bucket.tfstate[0].id : ""
}
