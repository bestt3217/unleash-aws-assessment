############################################
# Locals
############################################

locals {
  name_prefix = "unleash-assessment-${var.region}"

  # Parse user pool ARN like:
  # arn:aws:cognito-idp:us-east-1:ACCOUNT:userpool/us-east-1_XXXX
  user_pool_region = element(split(":", var.user_pool_arn), 3)
  user_pool_id     = element(split("/", var.user_pool_arn), 1)
  user_pool_issuer = "https://cognito-idp.${local.user_pool_region}.amazonaws.com/${local.user_pool_id}"

  ecs_sns_message = jsonencode({
    email  = var.email
    source = "ECS"
    region = var.region
    repo   = var.repo_url
  })
}

############################################
# DynamoDB (regional)
############################################

resource "aws_dynamodb_table" "greeting_logs" {
  name         = "GreetingLogs"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"

  attribute {
    name = "pk"
    type = "S"
  }

  tags = {
    Name = "${local.name_prefix}-ddb"
  }
}

############################################
# IAM shared: Lambda assume role
############################################

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

############################################
# Lambda: Greeter (writes DDB + publishes SNS)
############################################

resource "aws_iam_role" "greeter" {
  name               = "${local.name_prefix}-greeter-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "greeter_policy" {
  statement {
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["*"]
  }

  statement {
    actions   = ["dynamodb:PutItem"]
    resources = [aws_dynamodb_table.greeting_logs.arn]
  }

  statement {
    actions   = ["sns:Publish"]
    resources = [var.sns_topic_arn]
  }
}

resource "aws_iam_role_policy" "greeter_inline" {
  role   = aws_iam_role.greeter.id
  policy = data.aws_iam_policy_document.greeter_policy.json
}

data "archive_file" "greeter_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_greeter"
  output_path = "${path.module}/lambda_greeter.zip"
}

resource "aws_lambda_function" "greeter" {
  function_name = "${local.name_prefix}-greeter"
  role          = aws_iam_role.greeter.arn
  handler       = "app.handler"
  runtime       = "python3.11"

  filename         = data.archive_file.greeter_zip.output_path
  source_code_hash = data.archive_file.greeter_zip.output_base64sha256

  environment {
    variables = {
      TABLE_NAME    = aws_dynamodb_table.greeting_logs.name
      SNS_TOPIC_ARN = var.sns_topic_arn
      SNS_REGION    = "us-east-1"
      EMAIL         = var.email
      REPO_URL      = var.repo_url
    }
  }

  tags = {
    Name = "${local.name_prefix}-greeter"
  }
}

############################################
# Networking for ECS (public subnet, no NAT)
############################################

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = "10.10.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-igw"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.10.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name_prefix}-public-subnet"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-public-rt"
  }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "ecs" {
  name        = "${local.name_prefix}-ecs-sg"
  description = "ECS task SG (egress only)"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-ecs-sg"
  }
}

############################################
# ECS: Cluster + Roles + Task Definition
############################################

resource "aws_ecs_cluster" "cluster" {
  name = "${local.name_prefix}-cluster"

  tags = {
    Name = "${local.name_prefix}-cluster"
  }
}

# ECS task roles
data "aws_iam_policy_document" "ecs_task_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_task_execution" {
  name               = "${local.name_prefix}-ecs-task-exec-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_attach" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task_role" {
  name               = "${local.name_prefix}-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json
}

data "aws_iam_policy_document" "ecs_task_policy" {
  statement {
    actions   = ["sns:Publish"]
    resources = [var.sns_topic_arn]
  }
}

resource "aws_iam_role_policy" "ecs_task_inline" {
  role   = aws_iam_role.ecs_task_role.id
  policy = data.aws_iam_policy_document.ecs_task_policy.json
}

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${local.name_prefix}"
  retention_in_days = 7
}

resource "aws_ecs_task_definition" "sns_publisher" {
  family                   = "${local.name_prefix}-sns-publisher"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"

  execution_role_arn = aws_iam_role.ecs_task_execution.arn
  task_role_arn      = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "publisher"
      image     = "amazon/aws-cli:2.15.0"
      essential = true

      # Topic is in us-east-1, so publish using that region
      command = [
        "sns", "publish",
        "--region", "us-east-1",
        "--topic-arn", var.sns_topic_arn,
        "--message", local.ecs_sns_message
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  tags = {
    Name = "${local.name_prefix}-taskdef"
  }
}

############################################
# Lambda: Dispatcher (calls ECS RunTask)
############################################

resource "aws_iam_role" "dispatcher" {
  name               = "${local.name_prefix}-dispatcher-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "dispatcher_policy" {
  statement {
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["*"]
  }

  # RunTask on our task definition
  statement {
    actions   = ["ecs:RunTask"]
    resources = [aws_ecs_task_definition.sns_publisher.arn]
  }

  # Allow passing the ECS task roles to ECS
  statement {
    actions = ["iam:PassRole"]
    resources = [
      aws_iam_role.ecs_task_execution.arn,
      aws_iam_role.ecs_task_role.arn
    ]
  }
}

resource "aws_iam_role_policy" "dispatcher_inline" {
  role   = aws_iam_role.dispatcher.id
  policy = data.aws_iam_policy_document.dispatcher_policy.json
}

data "archive_file" "dispatcher_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_dispatcher"
  output_path = "${path.module}/lambda_dispatcher.zip"
}

resource "aws_lambda_function" "dispatcher" {
  function_name = "${local.name_prefix}-dispatcher"
  role          = aws_iam_role.dispatcher.arn
  handler       = "app.handler"
  runtime       = "python3.11"

  filename         = data.archive_file.dispatcher_zip.output_path
  source_code_hash = data.archive_file.dispatcher_zip.output_base64sha256

  environment {
    variables = {
      CLUSTER_ARN       = aws_ecs_cluster.cluster.arn
      TASK_DEF_ARN      = aws_ecs_task_definition.sns_publisher.arn
      SUBNET_ID         = aws_subnet.public.id
      SECURITY_GROUP_ID = aws_security_group.ecs.id
    }
  }

  tags = {
    Name = "${local.name_prefix}-dispatcher"
  }
}

############################################
# API Gateway HTTP API + Cognito JWT Authorizer
############################################

resource "aws_apigatewayv2_api" "api" {
  name          = "${local.name_prefix}-api"
  protocol_type = "HTTP"

  tags = {
    Name = "${local.name_prefix}-api"
  }
}

resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id          = aws_apigatewayv2_api.api.id
  name            = "${local.name_prefix}-cognito-jwt"
  authorizer_type = "JWT"

  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    issuer   = local.user_pool_issuer
    audience = [var.user_pool_client_id]
  }
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "$default"
  auto_deploy = true
}

############################################
# /greet route -> greeter lambda (JWT protected)
############################################

resource "aws_apigatewayv2_integration" "greeter" {
  api_id                 = aws_apigatewayv2_api.api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.greeter.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "greet" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "GET /greet"
  target    = "integrations/${aws_apigatewayv2_integration.greeter.id}"

  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_lambda_permission" "allow_apigw_greeter" {
  statement_id  = "AllowExecutionFromAPIGateway-Greeter-${var.region}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.greeter.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}

############################################
# /dispatch route -> dispatcher lambda (JWT protected)
############################################

resource "aws_apigatewayv2_integration" "dispatcher" {
  api_id                 = aws_apigatewayv2_api.api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.dispatcher.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "dispatch" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "POST /dispatch"
  target    = "integrations/${aws_apigatewayv2_integration.dispatcher.id}"

  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_lambda_permission" "allow_apigw_dispatcher" {
  statement_id  = "AllowExecutionFromAPIGateway-Dispatcher-${var.region}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.dispatcher.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}
