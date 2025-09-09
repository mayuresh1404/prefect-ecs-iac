provider "aws" {
  region = var.aws_region
}

# =================
# VPC & Networking
# =================
resource "aws_vpc" "prefect_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "prefect-ecs"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.prefect_vpc.id
  tags = {
    Name = "prefect-ecs-igw"
  }
}

data "aws_availability_zones" "available" {}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.prefect_vpc.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  tags = { Name = "prefect-public-${count.index}" }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.prefect_vpc.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = { Name = "prefect-private-${count.index}" }
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat" {
  depends_on = [aws_internet_gateway.igw]
}

# NAT Gateway in first public subnet
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  tags = {
    Name = "prefect-nat"
  }
  depends_on = [aws_internet_gateway.igw, aws_eip.nat]
}


resource "aws_route_table" "public" {
  vpc_id = aws_vpc.prefect_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "prefect-public-rt" }
}

resource "aws_route_table_association" "public" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.prefect_vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  tags = { Name = "prefect-private-rt" }
}

resource "aws_route_table_association" "private" {
  count          = length(var.private_subnet_cidrs)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# =================
# ECS Cluster
# =================
resource "aws_ecs_cluster" "prefect_cluster" {
  name = "prefect-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = { Name = "prefect-ecs" }
}

# =================
# IAM Roles
# =================
resource "aws_iam_role" "ecs_task_execution" {
  name = "prefect-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_attach" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_policy" "secrets_read_policy" {
  name        = "PrefectSecretsReadPolicy"
  description = "Allow reading Prefect API key from Secrets Manager"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "secrets_attach" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = aws_iam_policy.secrets_read_policy.arn
}

# =================
# Prefect API Key in Secrets Manager
# =================
resource "aws_secretsmanager_secret" "prefect_api_key" {
  name = var.prefect_api_key_secret_name
}

resource "aws_secretsmanager_secret_version" "prefect_api_key_value" {
  secret_id     = aws_secretsmanager_secret.prefect_api_key.id
  secret_string = jsonencode({ PREFECT_API_KEY = "" }) # Replace locally with your API key
}

# =================
# ECS Task Definition
# =================
resource "aws_ecs_task_definition" "prefect_worker" {
  family                   = "dev-worker"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([{
    name      = "dev-worker"
    image     = "prefecthq/prefect:2-latest"
    essential = true
    environment = [
      { name = "PREFECT_ACCOUNT_ID", value = var.prefect_account_id },
      { name = "PREFECT_WORKSPACE_ID", value = var.prefect_workspace_id },
      { name = "PREFECT_ACCOUNT_URL", value = var.prefect_account_url },
      { name = "PREFECT_WORK_POOL", value = var.ecs_work_pool }
    ]
    secrets = [
      {
        name      = "PREFECT_API_KEY"
        valueFrom = aws_secretsmanager_secret.prefect_api_key.arn
      }
    ]
  }])
}

# =================
# ECS Service
# =================
resource "aws_ecs_service" "prefect_worker_service" {
  name            = "dev-worker-service"
  cluster         = aws_ecs_cluster.prefect_cluster.id
  task_definition = aws_ecs_task_definition.prefect_worker.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = aws_subnet.private[*].id
    security_groups = [aws_security_group.ecs_sg.id]
    assign_public_ip = false
  }

  depends_on = [aws_iam_role_policy_attachment.ecs_task_execution_attach]
}

# =================
# Security Group
# =================
resource "aws_security_group" "ecs_sg" {
  name        = "prefect-ecs-sg"
  description = "Allow all outbound for ECS tasks"
  vpc_id      = aws_vpc.prefect_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = []
  }

  tags = { Name = "prefect-ecs-sg" }
}
