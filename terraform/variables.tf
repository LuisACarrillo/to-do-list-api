variable "aws_region" {
  description = "Región donde se crea la infraestructura."
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

variable "app_version" {
  description = "Valor inicial de APP_VERSION. El deploy de un release lo reemplaza con el tag."
  type        = string
  default     = "dev"
}
