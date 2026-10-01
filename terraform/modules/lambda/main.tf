data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${var.prefix}-ingestion-lambda"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_xray" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_iam_role_policy" "lambda_sqs" {
  name = "${var.prefix}-lambda-sqs"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sqs:SendMessage"]
      Resource = [var.sqs_queue_arn]
    }]
  })
}

# Package Lambda code
data "archive_file" "ingestion" {
  type        = "zip"
  source_dir  = "${path.module}/../../../app/ingestion"
  output_path = "${path.module}/../../../app/ingestion.zip"
}

resource "aws_lambda_function" "ingestion" {
  function_name = "${var.prefix}-ingestion"
  role          = aws_iam_role.lambda.arn
  filename      = data.archive_file.ingestion.output_path
  handler       = "handler.lambda_handler"
  runtime       = "python3.12"
  timeout       = 30
  memory_size   = 256

  source_code_hash = data.archive_file.ingestion.output_base64sha256

  environment {
    variables = {
      SQS_QUEUE_URL        = var.sqs_queue_url
      ENABLE_OBSERVABILITY = tostring(var.enable_observability)
      LOG_LEVEL            = "INFO"
      POWERTOOLS_SERVICE_NAME = "${var.prefix}-ingestion"
      AWS_LAMBDA_EXEC_WRAPPER = var.enable_observability ? "/opt/otel-instrument" : ""
    }
  }

  # ADOT Lambda Layer — only attached when observability is enabled
  layers = var.enable_observability ? [
    "arn:aws:lambda:${var.aws_region}:901920570463:layer:aws-otel-python-amd64-ver-1-21-0:1"
  ] : []

  tracing_config {
    mode = var.xray_tracing_mode
  }

  tags = { Name = "${var.prefix}-ingestion" }
}

resource "aws_lambda_function_url" "ingestion" {
  function_name      = aws_lambda_function.ingestion.function_name
  authorization_type = "NONE" # demo only
}
