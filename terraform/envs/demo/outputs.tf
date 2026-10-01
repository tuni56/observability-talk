output "api_endpoint" {
  description = "API Gateway endpoint URL — use this to send test requests"
  value       = module.api_gateway.endpoint_url
}

output "sqs_queue_url" {
  description = "SQS queue URL"
  value       = module.sqs.queue_url
}

output "dynamodb_table_name" {
  description = "DynamoDB table name"
  value       = module.dynamodb.table_name
}

output "s3_bucket_name" {
  description = "S3 raw data bucket name"
  value       = module.s3.bucket_name
}

output "cloudwatch_dashboard_url" {
  description = "CloudWatch dashboard URL"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${module.observability.dashboard_name}"
}

output "xray_traces_url" {
  description = "X-Ray traces console URL"
  value       = "https://${var.aws_region}.console.aws.amazon.com/xray/home?region=${var.aws_region}#/traces"
}
