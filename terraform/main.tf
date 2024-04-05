provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      "owner_name"  = var.owner_name
      "owner_email" = var.owner_email
    }
  }
}

variable "aws_region" {
  description = "aws region to use (global to script)"
}
variable "owner_name" {
  description = "used for the owner_name tag"
}
variable "owner_email" {
  description = "used for the owner_email tag"
}
variable "lab_name" {
  description = "base name for resources"
}

data "local_file" "version" {
  filename = "../VERSION"
}

#
# IAM
#

resource "aws_iam_role" "lambda_role" {
  name               = "${var.lab_name}-labmda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      },
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "lambda_s3" {
  name = "${var.lab_name}-s3-policy"
  description = "s3 access for lambda to bootstrap zip file"
  policy = jsonencode({
  Version = "2012-10-17",
  Statement = [
    {
      Action = [
        "s3:GetObject"
      ],
      Effect = "Allow",
      Resource = [
        "arn:aws:s3:::${aws_s3_bucket.lambda_repo.bucket}/*"
      ]
    }
  ]
})
}

resource "aws_iam_role_policy_attachment" "lambda_role_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "s3" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_s3.arn
}

#
#  app --> s3
#

resource "aws_s3_bucket" "lambda_repo" {
  # the bucket id
  bucket = "${var.lab_name}-repo"

  tags = {
    # bucket name (can be pretty)
    Name = "${var.lab_name}-repo"
  }
}

resource "aws_s3_object" "app_zip" {
  bucket = aws_s3_bucket.lambda_repo.bucket
  key    = "app-${data.local_file.version.content}.zip"
  source = "../build/app-${data.local_file.version.content}.zip"

  # The filemd5() function is available in Terraform 0.11.12 and later
  # For Terraform 0.11.11 and earlier, use the md5() function and the file() function:
  # etag = "${md5(file("path/to/file"))}"
  etag = filemd5("../build/app-${data.local_file.version.content}.zip")
}

#
# Lamda Function
#

resource "aws_lambda_function" "function" {
  function_name    = "${var.lab_name}-lambda"
  role             = aws_iam_role.lambda_role.arn
  s3_bucket = aws_s3_object.app_zip.bucket
  s3_key = aws_s3_object.app_zip.key
  timeout = 300
  runtime = "provided.al2023"
  handler       = "anything"

  environment {
    variables = {
      # Add environment variables if needed
      AVAR="a value"
    }
  }
}


#
# API Gateway
#

resource "aws_apigatewayv2_api" "lambda" {
  name          = "${var.lab_name}_lambda_gw"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "lambda" {
  api_id = aws_apigatewayv2_api.lambda.id

  name        = "${var.lab_name}_lambda_stage"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw.arn

    format = jsonencode({
      requestId               = "$context.requestId"
      sourceIp                = "$context.identity.sourceIp"
      requestTime             = "$context.requestTime"
      protocol                = "$context.protocol"
      httpMethod              = "$context.httpMethod"
      resourcePath            = "$context.resourcePath"
      routeKey                = "$context.routeKey"
      status                  = "$context.status"
      responseLength          = "$context.responseLength"
      integrationErrorMessage = "$context.integrationErrorMessage"
      }
    )
  }
}

resource "aws_apigatewayv2_integration" "integration" {
  api_id = aws_apigatewayv2_api.lambda.id

  integration_uri    = aws_lambda_function.function.invoke_arn
  integration_type   = "AWS_PROXY"
  integration_method = "POST"
}

resource "aws_apigatewayv2_route" "route" {
  api_id = aws_apigatewayv2_api.lambda.id

  route_key = "GET /hello"
  target    = "integrations/${aws_apigatewayv2_integration.integration.id}"
}


resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.function.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.lambda.execution_arn}/*/*"
}


#
# Logging
#

resource "aws_cloudwatch_log_group" "log" {
  name = "/aws/lambda/${aws_lambda_function.function.function_name}"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "api_gw" {
  name = "/aws/api_gw/${aws_apigatewayv2_api.lambda.name}"

  retention_in_days = 30
}


#
# outputs
#

output "base_url" {
  description = "Base URL for API Gateway stage."
  value = aws_apigatewayv2_stage.lambda.invoke_url
}

output "test_command" {
  description = "How to test this lambda"
  value = "curl -v ${aws_apigatewayv2_stage.lambda.invoke_url}/hello"
}