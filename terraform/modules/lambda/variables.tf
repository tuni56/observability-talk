variable "prefix"               { type = string }
variable "aws_region"           { type = string }
variable "sqs_queue_url"        { type = string }
variable "sqs_queue_arn"        { type = string }
variable "enable_observability" { type = bool }
variable "xray_tracing_mode"    { type = string }
