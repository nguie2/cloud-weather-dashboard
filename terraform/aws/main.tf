# AWS Provider Configuration
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# DynamoDB Table for Weather Data
resource "aws_dynamodb_table" "weather_data" {
  name           = "${var.project_name}-weather-data"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "location_id"
  range_key      = "timestamp"
  stream_enabled = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  attribute {
    name = "location_id"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "S"
  }

  attribute {
    name = "cloud_provider"
    type = "S"
  }

  global_secondary_index {
    name     = "CloudProviderIndex"
    hash_key = "cloud_provider"
    range_key = "timestamp"
  }

  tags = {
    Name        = "${var.project_name}-weather-data"
    Environment = var.environment
    Project     = var.project_name
  }
}

# S3 Bucket for Lambda deployment packages
resource "aws_s3_bucket" "lambda_deployments" {
  bucket = "${var.project_name}-lambda-deployments-${random_id.bucket_suffix.hex}"
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket_versioning" "lambda_deployments" {
  bucket = aws_s3_bucket.lambda_deployments.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "lambda_deployments" {
  bucket = aws_s3_bucket.lambda_deployments.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# IAM Role for Lambda functions
resource "aws_iam_role" "lambda_execution_role" {
  name = "${var.project_name}-lambda-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy for Lambda functions
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.project_name}-lambda-policy"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.weather_data.arn,
          "${aws_dynamodb_table.weather_data.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = aws_secretsmanager_secret.weather_api_keys.arn
      },
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = "*"
      }
    ]
  })
}

# Secrets Manager for API Keys
resource "aws_secretsmanager_secret" "weather_api_keys" {
  name        = "${var.project_name}-weather-api-keys"
  description = "API keys for weather data providers"
}

resource "aws_secretsmanager_secret_version" "weather_api_keys" {
  secret_id = aws_secretsmanager_secret.weather_api_keys.id
  secret_string = jsonencode({
    openweather_api_key = var.openweather_api_key
    weather_api_key     = var.weather_api_key
    accuweather_api_key = var.accuweather_api_key
  })
}

# Lambda function for weather data fetching
data "archive_file" "weather_lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../../lambda/aws"
  output_path = "${path.module}/weather-lambda.zip"
}

resource "aws_lambda_function" "weather_fetcher" {
  filename         = data.archive_file.weather_lambda_zip.output_path
  function_name    = "${var.project_name}-weather-fetcher"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "index.handler"
  source_code_hash = data.archive_file.weather_lambda_zip.output_base64sha256
  runtime         = "nodejs18.x"
  timeout         = 30

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.weather_data.name
      SECRET_ARN     = aws_secretsmanager_secret.weather_api_keys.arn
      CLOUD_PROVIDER = "aws"
    }
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# Lambda function for cross-cloud aggregation
data "archive_file" "aggregation_lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../../lambda/aggregation"
  output_path = "${path.module}/aggregation-lambda.zip"
}

resource "aws_lambda_function" "weather_aggregator" {
  filename         = data.archive_file.aggregation_lambda_zip.output_path
  function_name    = "${var.project_name}-weather-aggregator"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "index.handler"
  source_code_hash = data.archive_file.aggregation_lambda_zip.output_base64sha256
  runtime         = "nodejs18.x"
  timeout         = 60

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.weather_data.name
      AZURE_FUNCTION_URL = var.azure_function_url
      GCP_FUNCTION_URL   = var.gcp_function_url
    }
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "weather_fetcher_logs" {
  name              = "/aws/lambda/${aws_lambda_function.weather_fetcher.function_name}"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "weather_aggregator_logs" {
  name              = "/aws/lambda/${aws_lambda_function.weather_aggregator.function_name}"
  retention_in_days = 14
}

# API Gateway
resource "aws_api_gateway_rest_api" "weather_api" {
  name        = "${var.project_name}-weather-api"
  description = "Weather API Gateway"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "weather_resource" {
  rest_api_id = aws_api_gateway_rest_api.weather_api.id
  parent_id   = aws_api_gateway_rest_api.weather_api.root_resource_id
  path_part   = "weather"
}

resource "aws_api_gateway_resource" "aggregate_resource" {
  rest_api_id = aws_api_gateway_rest_api.weather_api.id
  parent_id   = aws_api_gateway_resource.weather_resource.id
  path_part   = "aggregate"
}

resource "aws_api_gateway_method" "weather_get" {
  rest_api_id   = aws_api_gateway_rest_api.weather_api.id
  resource_id   = aws_api_gateway_resource.weather_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "aggregate_get" {
  rest_api_id   = aws_api_gateway_rest_api.weather_api.id
  resource_id   = aws_api_gateway_resource.aggregate_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "weather_integration" {
  rest_api_id = aws_api_gateway_rest_api.weather_api.id
  resource_id = aws_api_gateway_resource.weather_resource.id
  http_method = aws_api_gateway_method.weather_get.http_method

  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.weather_fetcher.invoke_arn
}

resource "aws_api_gateway_integration" "aggregate_integration" {
  rest_api_id = aws_api_gateway_rest_api.weather_api.id
  resource_id = aws_api_gateway_resource.aggregate_resource.id
  http_method = aws_api_gateway_method.aggregate_get.http_method

  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.weather_aggregator.invoke_arn
}

# Lambda permissions for API Gateway
resource "aws_lambda_permission" "weather_api_gateway" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.weather_fetcher.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.weather_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "aggregate_api_gateway" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.weather_aggregator.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.weather_api.execution_arn}/*/*"
}

# API Gateway Deployment
resource "aws_api_gateway_deployment" "weather_deployment" {
  depends_on = [
    aws_api_gateway_integration.weather_integration,
    aws_api_gateway_integration.aggregate_integration,
  ]

  rest_api_id = aws_api_gateway_rest_api.weather_api.id
  stage_name  = var.environment

  lifecycle {
    create_before_destroy = true
  }
}

# EventBridge rule for scheduled weather data fetching
resource "aws_cloudwatch_event_rule" "weather_schedule" {
  name                = "${var.project_name}-weather-schedule"
  description         = "Trigger weather data fetching every 15 minutes"
  schedule_expression = "rate(15 minutes)"
}

resource "aws_cloudwatch_event_target" "weather_lambda_target" {
  rule      = aws_cloudwatch_event_rule.weather_schedule.name
  target_id = "WeatherLambdaTarget"
  arn       = aws_lambda_function.weather_fetcher.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.weather_fetcher.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.weather_schedule.arn
} 