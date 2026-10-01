# ── Log Groups ────────────────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.prefix}/processor"
  retention_in_days = 7 # demo — keep costs low
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.lambda_function_name}"
  retention_in_days = 7
}

# ── SNS Topics (P1 and P2 alert tiers) ───────────────────────────────────────

resource "aws_sns_topic" "p1" {
  name = "${var.prefix}-alerts-p1"
}

resource "aws_sns_topic" "p2" {
  name = "${var.prefix}-alerts-p2"
}

resource "aws_sns_topic_subscription" "p1_email" {
  topic_arn = aws_sns_topic.p1.arn
  protocol  = "email"
  endpoint  = var.sns_alert_email
}

resource "aws_sns_topic_subscription" "p2_email" {
  topic_arn = aws_sns_topic.p2.arn
  protocol  = "email"
  endpoint  = var.sns_alert_email
}

# ── CloudWatch Alarms ─────────────────────────────────────────────────────────

# P1: Lambda error rate > 5% over 5 minutes
resource "aws_cloudwatch_metric_alarm" "lambda_errors_p1" {
  alarm_name          = "${var.prefix}-lambda-error-rate-p1"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 5

  metric_query {
    id          = "error_rate"
    expression  = "errors / MAX([errors, invocations]) * 100"
    label       = "Error Rate (%)"
    return_data = true
  }

  metric_query {
    id = "errors"
    metric {
      metric_name = "Errors"
      namespace   = "AWS/Lambda"
      period      = 300
      stat        = "Sum"
      dimensions  = { FunctionName = var.lambda_function_name }
    }
  }

  metric_query {
    id = "invocations"
    metric {
      metric_name = "Invocations"
      namespace   = "AWS/Lambda"
      period      = 300
      stat        = "Sum"
      dimensions  = { FunctionName = var.lambda_function_name }
    }
  }

  alarm_actions = [aws_sns_topic.p1.arn]
  ok_actions    = [aws_sns_topic.p1.arn]

  alarm_description = "P1: Lambda error rate exceeded 5%. Check X-Ray traces for root cause."
  treat_missing_data = "notBreaching"

  tags = { Runbook = "https://github.com/your-org/runbooks/lambda-errors", Tier = "P1" }
}

# P2: Lambda P99 latency > 3000ms sustained for 10 minutes
resource "aws_cloudwatch_metric_alarm" "lambda_latency_p2" {
  alarm_name          = "${var.prefix}-lambda-p99-latency-p2"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 3000
  period              = 300
  statistic           = "p99"
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"

  dimensions = { FunctionName = var.lambda_function_name }

  alarm_actions = [aws_sns_topic.p2.arn]
  ok_actions    = [aws_sns_topic.p2.arn]

  alarm_description  = "P2: Lambda P99 latency above 3s for 10 min. Check X-Ray for slow segments."
  treat_missing_data = "notBreaching"

  tags = { Runbook = "https://github.com/your-org/runbooks/latency", Tier = "P2" }
}

# P1: Dead Letter Queue has messages (guaranteed failures)
resource "aws_cloudwatch_metric_alarm" "dlq_messages_p1" {
  alarm_name          = "${var.prefix}-dlq-messages-p1"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 0
  period              = 60
  statistic           = "Sum"
  metric_name         = "NumberOfMessagesSent"
  namespace           = "AWS/SQS"

  dimensions = { QueueName = var.dlq_name }

  alarm_actions = [aws_sns_topic.p1.arn]

  alarm_description  = "P1: Messages arriving in DLQ — processing failures after 3 retries."
  treat_missing_data = "notBreaching"

  tags = { Runbook = "https://github.com/your-org/runbooks/dlq", Tier = "P1" }
}

# ── CloudWatch Dashboard ──────────────────────────────────────────────────────

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.prefix}-observability"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "text"
        x      = 0; y = 0; width = 24; height = 2
        properties = {
          markdown = "# ${var.prefix} — Observability Dashboard\n**The Cost of Validation: Adding Governance Without Creating Bottlenecks** | Community Day South Florida"
        }
      },
      {
        type   = "metric"
        x      = 0; y = 2; width = 8; height = 6
        properties = {
          title  = "Lambda Invocations & Errors"
          period = 60
          stat   = "Sum"
          view   = "timeSeries"
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", var.lambda_function_name],
            ["AWS/Lambda", "Errors",      "FunctionName", var.lambda_function_name, { color = "#d62728" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 8; y = 2; width = 8; height = 6
        properties = {
          title  = "Lambda Duration (P50 / P99)"
          period = 60
          view   = "timeSeries"
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", var.lambda_function_name, { stat = "p50", label = "P50" }],
            ["AWS/Lambda", "Duration", "FunctionName", var.lambda_function_name, { stat = "p99", label = "P99", color = "#ff7f0e" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 16; y = 2; width = 8; height = 6
        properties = {
          title  = "SQS Queue Depth & DLQ"
          period = 60
          stat   = "Maximum"
          view   = "timeSeries"
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible",    "QueueName", var.sqs_queue_name, { label = "Queue Depth" }],
            ["AWS/SQS", "ApproximateNumberOfMessagesNotVisible", "QueueName", var.sqs_queue_name, { label = "In-flight" }],
            ["AWS/SQS", "NumberOfMessagesSent",                  "QueueName", var.dlq_name,       { label = "DLQ Messages", color = "#d62728" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 0; y = 8; width = 12; height = 6
        properties = {
          title  = "ECS CPU & Memory Utilization"
          period = 60
          stat   = "Average"
          view   = "timeSeries"
          metrics = [
            ["AWS/ECS", "CPUUtilization",    "ClusterName", var.ecs_cluster_name, "ServiceName", var.ecs_service_name],
            ["AWS/ECS", "MemoryUtilization", "ClusterName", var.ecs_cluster_name, "ServiceName", var.ecs_service_name, { color = "#9467bd" }]
          ]
        }
      },
      {
        type   = "log"
        x      = 12; y = 8; width = 12; height = 6
        properties = {
          title   = "Recent Errors (Structured Logs)"
          region  = var.aws_region
          query   = "SOURCE '/ecs/${var.prefix}/processor' | filter level = \"ERROR\" | fields timestamp, service, error_type, message | sort @timestamp desc | limit 20"
          view    = "table"
        }
      }
    ]
  })
}
