# ─── IAM Roles ───
#
# Em uma conta AWS normal, este código cria as roles do cluster e dos nós.
# Em ambientes restritos (ex.: AWS Academy Learner Lab), onde criar IAM roles
# é bloqueado, informe uma role pré-existente em var.lab_role_arn (ex.: LabRole)
# e ela é reutilizada para o cluster e para os worker nodes.

locals {
  use_lab_role     = var.lab_role_arn != ""
  cluster_role_arn = local.use_lab_role ? var.lab_role_arn : aws_iam_role.cluster[0].arn
  node_role_arn    = local.use_lab_role ? var.lab_role_arn : aws_iam_role.node[0].arn
}

# ─── IAM Role para o Cluster EKS (apenas quando NÃO se usa a lab_role) ───

resource "aws_iam_role" "cluster" {
  count = local.use_lab_role ? 0 : 1
  name  = "${var.project_name}-${var.environment}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  count      = local.use_lab_role ? 0 : 1
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster[0].name
}

resource "aws_iam_role_policy_attachment" "cluster_vpc_controller" {
  count      = local.use_lab_role ? 0 : 1
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.cluster[0].name
}

# ─── IAM Role para os Worker Nodes (apenas quando NÃO se usa a lab_role) ───

resource "aws_iam_role" "node" {
  count = local.use_lab_role ? 0 : 1
  name  = "${var.project_name}-${var.environment}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "node_worker" {
  count      = local.use_lab_role ? 0 : 1
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node[0].name
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  count      = local.use_lab_role ? 0 : 1
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node[0].name
}

resource "aws_iam_role_policy_attachment" "node_ecr" {
  count      = local.use_lab_role ? 0 : 1
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node[0].name
}

# ─── Security Group do Cluster ───

resource "aws_security_group" "cluster" {
  name        = "${var.project_name}-${var.environment}-eks-cluster-sg"
  description = "Security group para o cluster EKS"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-eks-cluster-sg"
  }
}

# ─── Security Group dos Nodes ───

resource "aws_security_group" "node" {
  name        = "${var.project_name}-${var.environment}-eks-node-sg"
  description = "Security group para os worker nodes do EKS"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Comunicacao com o cluster"
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.cluster.id]
  }

  ingress {
    description = "Comunicacao entre nodes"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-eks-node-sg"
  }
}

# ─── Cluster EKS ───

resource "aws_eks_cluster" "main" {
  name     = "${var.project_name}-${var.environment}"
  version  = var.cluster_version
  role_arn = local.cluster_role_arn

  vpc_config {
    subnet_ids              = aws_subnet.private[*].id
    security_group_ids      = [aws_security_group.cluster.id]
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  access_config {
    authentication_mode = "API_AND_CONFIG_MAP"
    # Concede admin ao principal que CRIA o cluster (no AWS Academy, a role
    # "voclabs" usada pelo Terraform Cloud). Isso é feito pelo próprio EKS no
    # momento da criação — NÃO usa eks:CreateAccessEntry, que a voclabs tem
    # bloqueado por um deny explícito (policy "voc-cancel-cred"). Assim o kubectl
    # funciona logo após o apply, sem passo manual de Access Entry.
    bootstrap_cluster_creator_admin_permissions = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy,
    aws_iam_role_policy_attachment.cluster_vpc_controller,
  ]
}

# ─── Node Group ───

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project_name}-${var.environment}-nodes"
  node_role_arn   = local.node_role_arn
  subnet_ids      = aws_subnet.private[*].id
  instance_types  = [var.node_instance_type]

  scaling_config {
    desired_size = var.node_desired_count
    min_size     = var.node_min_count
    max_size     = var.node_max_count
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_ecr,
  ]
}

# ─── Controle de acesso ao cluster (Access Entry + Access Policy Association) ───
#
# Concede acesso de administrador do cluster a um IAM role/usuário informado em
# var.access_entry_role_arn (ex.: a LabRole no AWS Academy ou seu usuário IAM).
# Igual ao modelo da aula. Fica desativado quando a variável está vazia.

resource "aws_eks_access_entry" "admin" {
  count         = var.access_entry_role_arn != "" ? 1 : 0
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = var.access_entry_role_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "admin" {
  count         = var.access_entry_role_arn != "" ? 1 : 0
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = var.access_entry_role_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.admin]
}
