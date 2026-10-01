output "function_arn"  { value = aws_lambda_function.ingestion.arn }
output "function_name" { value = aws_lambda_function.ingestion.function_name }
output "function_url"  { value = aws_lambda_function_url.ingestion.function_url }
