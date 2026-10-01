output "dashboard_name"      { value = aws_cloudwatch_dashboard.main.dashboard_name }
output "ecs_log_group_name"  { value = aws_cloudwatch_log_group.ecs.name }
output "lambda_log_group"    { value = aws_cloudwatch_log_group.lambda.name }
output "sns_topic_p1_arn"    { value = aws_sns_topic.p1.arn }
output "sns_topic_p2_arn"    { value = aws_sns_topic.p2.arn }
