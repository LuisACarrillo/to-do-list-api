terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-kernel-6.1-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_rds_engine_version" "mysql" {
  engine  = "mysql"
  version = "8.0"
  latest  = true
}

resource "tls_private_key" "todo" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "todo" {
  key_name   = "todo-list-api-key"
  public_key = tls_private_key.todo.public_key_openssh
}

resource "local_sensitive_file" "private_key" {
  content         = tls_private_key.todo.private_key_pem
  filename        = "${path.module}/todo-list-api.pem"
  file_permission = "0400"
}

resource "aws_security_group" "todo" {
  name        = "todo-list-api-sg"
  description = "SSH y la API de tareas"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "API"
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Salida a internet para clonar el repo e instalar dependencias"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "todo-list-api-sg"
  }
}

resource "aws_security_group" "rds" {
  name        = "todo-list-api-rds-sg"
  description = "MySQL solo desde la instancia de la API"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "MySQL desde la EC2"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.todo.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "todo-list-api-rds-sg"
  }
}

resource "random_password" "db" {
  length  = 20
  special = false
}

resource "aws_db_subnet_group" "todo" {
  name       = "todo-list-api"
  subnet_ids = data.aws_subnets.default.ids

  tags = {
    Name = "todo-list-api"
  }
}

resource "aws_db_instance" "todo" {
  identifier              = "todo-list-api"
  engine                  = "mysql"
  engine_version          = data.aws_rds_engine_version.mysql.version
  instance_class          = "db.t3.micro"
  allocated_storage       = 20
  storage_type            = "gp2"
  db_name                 = "todo"
  username                = "todo"
  password                = random_password.db.result
  db_subnet_group_name    = aws_db_subnet_group.todo.name
  vpc_security_group_ids  = [aws_security_group.rds.id]
  publicly_accessible     = false
  skip_final_snapshot     = true
  backup_retention_period = 0
  deletion_protection     = false
  apply_immediately       = true

  tags = {
    Name = "todo-list-api"
  }
}

resource "aws_secretsmanager_secret" "db" {
  name                    = "todo-list-api/db"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    host     = aws_db_instance.todo.address
    port     = aws_db_instance.todo.port
    username = aws_db_instance.todo.username
    password = random_password.db.result
    dbname   = aws_db_instance.todo.db_name
  })
}

# El Learner Lab niega iam:CreateRole. LabInstanceProfile ya existe y usa LabRole.
resource "aws_instance" "todo" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.todo.key_name
  vpc_security_group_ids      = [aws_security_group.todo.id]
  iam_instance_profile        = "LabInstanceProfile"
  associate_public_ip_address = true
  user_data_replace_on_change = true
  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    repo_url    = var.repo_url
    secret_id   = aws_secretsmanager_secret.db.name
    aws_region  = var.aws_region
    app_version = var.app_version
  })

  depends_on = [aws_secretsmanager_secret_version.db]

  tags = {
    Name = "todo-list-api"
  }
}
