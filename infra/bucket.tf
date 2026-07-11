# ─── Bucket S3 + tabela DynamoDB para o state remoto do Terraform ───
#
# Cria a infraestrutura de "backend" (state remoto). É aplicado com state local
# na primeira vez; depois o backend.tf passa a apontar para este bucket.
# Defina var.state_bucket_name com um nome GLOBALMENTE único.

resource "aws_s3_bucket" "tfstate" {
  count  = var.create_state_backend ? 1 : 0
  bucket = var.state_bucket_name

  tags = {
    Name = "${var.project_name}-${var.environment}-tfstate"
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  count  = var.create_state_backend ? 1 : 0
  bucket = aws_s3_bucket.tfstate[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  count  = var.create_state_backend ? 1 : 0
  bucket = aws_s3_bucket.tfstate[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  count  = var.create_state_backend ? 1 : 0
  bucket = aws_s3_bucket.tfstate[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "tflock" {
  count        = var.create_state_backend ? 1 : 0
  name         = var.state_lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-tflock"
  }
}
