data "aws_caller_identity" "current" {}
data "aws_ecr_repository" "processor" {
  name = "${var.prefix}-processor"
}

# ── IAM ───────────────────────────────────────────────────────────────────────

data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_task_execution" {
  name               = "${var.prefix}-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task" {
  name               = "${var.prefix}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

resource "aws_iam_role_policy" "ecs_task_permissions" {
  name = "${var.prefix}-ecs-task-perms"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = [var.sqs_queue_arn]
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:GetItem"]
        Resource = [var.dynamodb_table_arn]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = ["${var.s3_bucket_arn}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords", "xray:GetSamplingRules"]
        Resource = ["*"]
      },
      {
        Effect   = "Allow"
        Action   = ["cloudwatch:PutMetricData", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = ["*"]
      }
    ]
  })
}

# ── Security Group ────────────────────────────────────────────────────────────

resource "aws_security_group" "ecs_processor" {
  name        = "${var.prefix}-processor-sg"
  description = "ECS processor — egress only"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.prefix}-processor-sg" }
}

# ── ECS Cluster ───────────────────────────────────────────────────────────────

resource "aws_ecs_cluster" "main" {
  name = "${var.prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = { Name = "${var.prefix}-cluster" }
}

# ── Task Definition ───────────────────────────────────────────────────────────

resource "aws_ecs_task_definition" "processor" {
  family                   = "${var.prefix}-processor"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    # ── Main processor container ──
    {
      name      = "processor"
      image     = "${data.aws_ecr_repository.processor.repository_url}:latest"
      essential = true

      environment = [
        { name = "SQS_QUEUE_URL",         value = var.sqs_queue_url },
        { name = "DYNAMODB_TABLE",        value = var.dynamodb_table_name },
        { name = "S3_BUCKET",             value = var.s3_bucket_name },
        { name = "AWS_REGION",            value = var.aws_region },
        { name = "ENABLE_OBSERVABILITY",  value = tostring(var.enable_observability) },
        { name = "INTRODUCE_LATENCY_BUG", value = tostring(var.introduce_latency_bug) },
        { name = "LOG_LEVEL",             value = "INFO" },
        { name = "OTEL_EXPORTER_OTLP_ENDPOINT", value = "http://localhost:4317" },
        { name = "OTEL_SERVICE_NAME",     value = "${var.prefix}-processor" },
        { name = "OTEL_PROPAGATORS",      value = "xray" },
        { name = "OTEL_PYTHON_ID_GENERATOR", value = "xray" }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = var.log_group_name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "processor"
        }
      }

      dependsOn = var.enable_observability ? [
        { containerName = "adot-collector", condition = "START" }
      ] : []
    },

    # ── ADOT Collector sidecar (only when observability is enabled) ──
    {
      name      = "adot-collector"
      image     = "public.ecr.aws/aws-observability/aws-otel-collector:v0.40.0"
      essential = false

      command = ["--config=/etc/ecs/ecs-xray.yaml"]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = var.log_group_name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "adot"
        }
      }
    }
  ])

  tags = { Name = "${var.prefix}-processor" }
}

# ── ECS Service ───────────────────────────────────────────────────────────────

resource "aws_ecs_service" "processor" {
  name            = "${var.prefix}-processor"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.processor.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.ecs_processor.id]
    assign_public_ip = false
  }

  # Allow task definition updates without destroying the service
  lifecycle {
    ignore_changes = [task_definition]
  }

  tags = { Name = "${var.prefix}-processor" }
}
