# Demo environment — root module
# Wires together all service modules

locals {
  prefix = "${var.project_name}-${var.environment}"
}

# ── Networking (VPC for ECS) ──────────────────────────────────────────────────
module "vpc" {
  source       = "../../modules/vpc"
  prefix       = local.prefix
  aws_region   = var.aws_region
}

# ── Storage ───────────────────────────────────────────────────────────────────
module "s3" {
  source      = "../../modules/s3"
  prefix      = local.prefix
}

module "dynamodb" {
  source      = "../../modules/dynamodb"
  prefix      = local.prefix
}

# ── Messaging ─────────────────────────────────────────────────────────────────
module "sqs" {
  source      = "../../modules/sqs"
  prefix      = local.prefix
}

# ── Observability (SNS + CloudWatch) ─────────────────────────────────────────
module "observability" {
  source               = "../../modules/observability"
  prefix               = local.prefix
  sns_alert_email      = var.sns_alert_email
  aws_region           = var.aws_region
  lambda_function_name = module.lambda.function_name
  ecs_cluster_name     = module.ecs.cluster_name
  ecs_service_name     = module.ecs.service_name
  sqs_queue_name       = module.sqs.queue_name
  dlq_name             = module.sqs.dlq_name
}

# ── Lambda (ingestion) ────────────────────────────────────────────────────────
module "lambda" {
  source               = "../../modules/lambda"
  prefix               = local.prefix
  aws_region           = var.aws_region
  sqs_queue_url        = module.sqs.queue_url
  sqs_queue_arn        = module.sqs.queue_arn
  enable_observability = var.enable_observability
  xray_tracing_mode    = var.enable_observability ? "Active" : "PassThrough"
}

# ── ECS Fargate (processor) ───────────────────────────────────────────────────
module "ecs" {
  source                = "../../modules/ecs"
  prefix                = local.prefix
  aws_region            = var.aws_region
  vpc_id                = module.vpc.vpc_id
  private_subnet_ids    = module.vpc.private_subnet_ids
  sqs_queue_url         = module.sqs.queue_url
  sqs_queue_arn         = module.sqs.queue_arn
  dynamodb_table_name   = module.dynamodb.table_name
  dynamodb_table_arn    = module.dynamodb.table_arn
  s3_bucket_name        = module.s3.bucket_name
  s3_bucket_arn         = module.s3.bucket_arn
  enable_observability  = var.enable_observability
  introduce_latency_bug = var.introduce_latency_bug
  log_group_name        = module.observability.ecs_log_group_name
}

# ── API Gateway ───────────────────────────────────────────────────────────────
module "api_gateway" {
  source               = "../../modules/api_gateway"
  prefix               = local.prefix
  lambda_function_arn  = module.lambda.function_arn
  lambda_function_name = module.lambda.function_name
  aws_region           = var.aws_region
}
