resource "aws_sqs_queue" "dlq" {
  name                      = "${var.prefix}-processor-dlq"
  message_retention_seconds = 1209600 # 14 days

  tags = { Name = "${var.prefix}-processor-dlq" }
}

resource "aws_sqs_queue" "main" {
  name                       = "${var.prefix}-processor"
  visibility_timeout_seconds = 300
  message_retention_seconds  = 86400 # 1 day for demo

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })

  tags = { Name = "${var.prefix}-processor" }
}
