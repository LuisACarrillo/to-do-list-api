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
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "Región donde se crea la instancia."
  type        = string
  default     = "us-east-1"
}

variable "repo_url" {
  description = "Repositorio que la instancia clona al arrancar."
  type        = string
  default     = "https://github.com/LuisACarrillo/to-do-list-api.git"
}

variable "instance_type" {
  description = "Tipo de instancia EC2."
  type        = string
  default     = "t3.micro"
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
  description = "SSH y HTTP para la API de tareas"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP de la API"
    from_port   = 80
    to_port     = 80
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

resource "aws_instance" "todo" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.todo.key_name
  vpc_security_group_ids      = [aws_security_group.todo.id]
  associate_public_ip_address = true
  user_data_replace_on_change = true
  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    repo_url = var.repo_url
  })

  tags = {
    Name = "todo-list-api"
  }
}

output "public_ip" {
  description = "IP pública de la instancia."
  value       = aws_instance.todo.public_ip
}

output "tasks_url" {
  description = "URL del endpoint GET /tasks."
  value       = "http://${aws_instance.todo.public_ip}/tasks"
}

output "ssh_command" {
  description = "Comando para entrar por SSH con la llave generada."
  value       = "ssh -i todo-list-api.pem ec2-user@${aws_instance.todo.public_ip}"
}
