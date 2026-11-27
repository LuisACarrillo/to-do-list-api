resource "aws_sns_topic" "alerts" {
  name = "todo-list-api-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "cpu" {
  alarm_name          = "todo-list-api-cpu-high"
  alarm_description   = "CPU de la EC2 por encima del 80% durante dos periodos de 5 minutos."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  dimensions = {
    InstanceId = aws_instance.todo.id
  }
  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "rds_errors" {
  alarm_name          = "todo-list-api-rds-errors"
  alarm_description   = "Al menos un error al leer o escribir en RDS en el último minuto."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "RDSErrors"
  namespace           = "TodoList"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "tasks_created" {
  alarm_name          = "todo-list-api-tasks-spike"
  alarm_description   = "Se crearon 50 o más tareas en 5 minutos."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "TasksCreated"
  namespace           = "TodoList"
  period              = 300
  statistic           = "Sum"
  threshold           = 50
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_dashboard" "todo" {
  dashboard_name = "todo-list-api"
  dashboard_body = templatefile("${path.module}/../alerting/cloudwatch-dashboard.json", {
    instance_id = aws_instance.todo.id
    aws_region  = var.aws_region
  })
}
