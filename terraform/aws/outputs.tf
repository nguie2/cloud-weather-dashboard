output "api_gateway_url" {
  description = "URL of the API Gateway"
  value       = "https://${aws_api_gateway_rest_api.weather_api.id}.execute-api.${var.aws_region}.amazonaws.com/${var.environment}"
}

output "weather_lambda_function_name" {
  description = "Name of the weather fetcher Lambda function"
  value       = aws_lambda_function.weather_fetcher.function_name
}

output "aggregator_lambda_function_name" {
  description = "Name of the weather aggregator Lambda function"
  value       = aws_lambda_function.weather_aggregator.function_name
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table"
  value       = aws_dynamodb_table.weather_data.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table"
  value       = aws_dynamodb_table.weather_data.arn
}

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "secrets_manager_secret_arn" {
  description = "ARN of the Secrets Manager secret"
  value       = aws_secretsmanager_secret.weather_api_keys.arn
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket for Lambda deployments"
  value       = aws_s3_bucket.lambda_deployments.bucket
}

output "cloudwatch_log_group_names" {
  description = "Names of CloudWatch log groups"
  value = {
    weather_fetcher   = aws_cloudwatch_log_group.weather_fetcher_logs.name
    weather_aggregator = aws_cloudwatch_log_group.weather_aggregator_logs.name
  }
} 