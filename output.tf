output "ecs_cluster_arn" {
  value       = aws_ecs_cluster.prefect_cluster.arn
  description = "ARN of the ECS cluster"
}

output "ecs_service_name" {
  value       = aws_ecs_service.prefect_worker_service.name
  description = "ECS Service running Prefect worker"
}
