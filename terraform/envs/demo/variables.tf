variable "aws_region" {
  description = "AWS region to deploy all resources"
  type        = string
  default     = "us-east-2"
}

variable "environment" {
  description = "Deployment environment name"
  type        = string
  default     = "demo"
}

variable "project_name" {
  description = "Project name used as prefix for all resources"
  type        = string
  default     = "obs-talk"
}

variable "sns_alert_email" {
  description = "Email address to receive CloudWatch alarm notifications"
  type        = string
  # Set via terraform.tfvars or TF_VAR_sns_alert_email
}

variable "enable_observability" {
  description = "Toggle ADOT instrumentation on/off — used during the live demo"
  type        = bool
  default     = true
}

variable "introduce_latency_bug" {
  description = "Toggle the artificial latency bottleneck in the processor — used during the live demo"
  type        = bool
  default     = false
}
