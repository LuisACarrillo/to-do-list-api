output "public_ip" {
  description = "IP pública de la instancia."
  value       = aws_instance.todo.public_ip
}

output "tasks_url" {
  description = "URL del endpoint GET /tasks."
  value       = "http://${aws_instance.todo.public_ip}:8000/tasks"
}

output "version_url" {
  description = "URL del endpoint GET /version."
  value       = "http://${aws_instance.todo.public_ip}:8000/version"
}

output "health_url" {
  description = "URL del endpoint GET /health."
  value       = "http://${aws_instance.todo.public_ip}:8000/health"
}

output "secret_name" {
  description = "Secret de Secrets Manager con las credenciales de RDS."
  value       = aws_secretsmanager_secret.db.name
}

output "ssh_command" {
  description = "Comando para entrar por SSH con la llave generada."
  value       = "ssh -i terraform/todo-list-api.pem ec2-user@${aws_instance.todo.public_ip}"
}

output "alerts_topic_arn" {
  description = "Tópico SNS al que avisan las tres alarmas."
  value       = aws_sns_topic.alerts.arn
}

output "dashboard_name" {
  description = "Dashboard de CloudWatch con las tres métricas."
  value       = aws_cloudwatch_dashboard.todo.dashboard_name
}
