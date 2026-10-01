variable "prefix"               { type = string }
variable "aws_region"           { type = string }
variable "sns_alert_email"      { type = string }
variable "lambda_function_name" { type = string }
variable "ecs_cluster_name"     { type = string }
variable "ecs_service_name"     { type = string }
variable "sqs_queue_name"       { type = string }
variable "dlq_name"             { type = string }
