output "cluster_name"  { value = aws_ecs_cluster.main.name }
output "service_name"  { value = aws_ecs_service.processor.name }
output "task_role_arn" { value = aws_iam_role.ecs_task.arn }
