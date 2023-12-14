terraform {
  backend "http" {}

  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

provider "aws" {
  region = var.region

  endpoints {
    apigateway       = var.is_localstack_deploy ? "http://localhost:4566" : null
    cloudwatch       = var.is_localstack_deploy ? "http://localhost:4566" : null
    cloudwatchevents = var.is_localstack_deploy ? "http://localhost:4566" : null
    iam              = var.is_localstack_deploy ? "http://localhost:4566" : null
    dynamodb         = var.is_localstack_deploy ? "http://localhost:4566" : null
    lambda           = var.is_localstack_deploy ? "http://localhost:4566" : null
    s3               = var.is_localstack_deploy ? "http://localhost:4566" : null
  }

  default_tags {
    tags = {
      DeploymentName = local.resource_prefix,
      Service        = local.project_name,
      Terraform      = true
    }
  }
}

locals {
  project_name        = "cm-api"
  resource_prefix     = "${local.project_name}-${var.stack_name}"
  project_root        = "${path.module}/.."
  src_path            = "${local.project_root}/src"
  dynamodb_table_name = "${local.resource_prefix}-dynamodb"
}

data "aws_iam_policy_document" "dynamodb_read_write" {
  statement {
    sid    = "DynamoDBIndexAndStreamAccess"
    effect = "Allow"
    actions = [
      "dynamodb:GetShardIterator",
      "dynamodb:Scan",
      "dynamodb:Query",
      "dynamodb:DescribeStream",
      "dynamodb:GetRecords",
      "dynamodb:ListStreams"
    ]
    resources = [
      "${aws_dynamodb_table.dynamodb_table.arn}/index/*",
      "${aws_dynamodb_table.dynamodb_table.arn}/stream/*"
    ]
  }
  statement {
    sid    = "DynamoDBTableAccess"
    effect = "Allow"
    actions = [
      "dynamodb:BatchGetItem",
      "dynamodb:BatchWriteItem",
      "dynamodb:ConditionCheckItem",
      "dynamodb:PutItem",
      "dynamodb:DescribeTable",
      "dynamodb:DeleteItem",
      "dynamodb:GetItem",
      "dynamodb:Scan",
      "dynamodb:Query",
      "dynamodb:UpdateItem"
    ]
    resources = [
      "${aws_dynamodb_table.dynamodb_table.arn}*"
    ]
  }
  statement {
    sid    = "DynamoDBDescribeLimitsAccess"
    effect = "Allow"
    actions = [
      "dynamodb:DescribeLimits"
    ]
    resources = [
      aws_dynamodb_table.dynamodb_table.arn,
      "${aws_dynamodb_table.dynamodb_table.arn}/index/*"
    ]
  }
}

resource "aws_dynamodb_table" "dynamodb_table" {
  name           = "${local.resource_prefix}-dynamodb"
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 1
  hash_key       = "pk"
  range_key      = "sk"

  attribute {
    name = "pk"
    type = "S"
  }

  attribute {
    name = "sk"
    type = "S"
  }

  provisioner "local-exec" {
    command = var.is_localstack_deploy ? "${local.project_root}/scripts/seed_data.sh ${local.resource_prefix}-dynamodb LOCAL" : "${local.project_root}/scripts/seed_data.sh ${local.resource_prefix}-dynamodb"
  }
}

resource "aws_iam_policy" "dynamodb_read_write" {
  name        = "${local.resource_prefix}-dynamodb-read-write"
  description = "Read and write permissions for the DyanmoDB Table for the '${local.project_name}' project"
  policy      = data.aws_iam_policy_document.dynamodb_read_write.json
}

resource "aws_iam_policy" "invoke_lambda_iam_policy" {
  name        = "${local.resource_prefix}-invoke-lambda"
  description = "IAM policy that allows the invocation of the lambdas associated to the '${local.project_name}' project"
  policy      = data.aws_iam_policy_document.lambda_invoke_policy_document.json
}

data "aws_iam_policy_document" "api_gateway_access_policy" {
  statement {
    actions   = ["execute-api:Invoke"]
    effect    = "Allow"
    resources = ["*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }
  }
}

resource "aws_iam_role" "api_gateway_role" {
  name        = "${local.resource_prefix}-api-gateway-executor"
  description = "The IAM role the API Gateway for the '${local.project_name}' project will use for the integration executions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_allow_api_gateway_to_invoke_lambda_policy" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = aws_iam_policy.invoke_lambda_iam_policy.arn
}

resource "aws_api_gateway_deployment" "api_gateway_deployment" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway_rest_api.id

  triggers = {
    redeployment = sha1(jsonencode(aws_api_gateway_rest_api.api_gateway_rest_api.body))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "api_gateway_deployed_stage_production" {
  deployment_id = aws_api_gateway_deployment.api_gateway_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.api_gateway_rest_api.id
  stage_name    = "production"
}

resource "aws_api_gateway_method_settings" "api_gateway_method_settings" {
  rest_api_id = aws_api_gateway_rest_api.api_gateway_rest_api.id
  stage_name  = aws_api_gateway_stage.api_gateway_deployed_stage_production.stage_name
  method_path = "*/*"

  settings {
    logging_level      = "INFO"
    data_trace_enabled = true
    metrics_enabled    = true
  }
}

## --- The resources below are kept at the bottom of this file intentionally
## --- As new endpoints are added, the resources below should be modified

resource "aws_api_gateway_rest_api" "api_gateway_rest_api" {
  name        = "${local.resource_prefix}-api"
  description = "API Gateway for the '${local.project_name}' project"

  body = templatefile("${local.src_path}/openapi.yaml", {
    consent_management_get_realms_arn                    = module.get_realms_lambda.lambda_function_arn
    consent_management_get_consent_document_versions_arn = module.get_consent_document_versions_lambda.lambda_function_arn
    consent_management_create_user_consent_event_arn     = module.create_user_consent_event_lambda.lambda_function_arn
    consent_management_get_current_consent_version_arn   = module.get_current_consent_version_lambda.lambda_function_arn
    gateway_iam_role_arn                                 = aws_iam_role.api_gateway_role.arn
    authorizer_uri                                       = module.lambda_authorizer.lambda_function_invoke_arn
    authorizer_credentials                               = aws_iam_role.api_gateway_role.arn
  })

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

data "aws_iam_policy_document" "lambda_invoke_policy_document" {
  statement {
    sid    = "LambdaInvoke"
    effect = "Allow"
    actions = [
      "lambda:InvokeFunction"
    ]
    resources = [
      module.lambda_authorizer.lambda_function_arn,
      module.get_realms_lambda.lambda_function_arn,
      module.create_user_consent_event_lambda.lambda_function_arn,
      module.get_current_consent_version_lambda.lambda_function_arn,
      module.get_consent_document_versions_lambda.lambda_function_arn,
    ]
  }
}

## --- The resources below are kept at the bottom of this file intentionally
## --- Keep the Lambda references below this line

module "lambda_authorizer" {
  source        = "terraform-aws-modules/lambda/aws"
  publish       = true
  function_name = "${local.resource_prefix}-lambda_authorizer"
  handler       = "app.lambda_handler"
  runtime       = "python3.11"
  timeout       = 900

  environment_variables = {
    UNIFIED_AUTH_JWKS_ENDPOINT = var.unified_auth_jwks_endpoint
  }

  source_path = [
    {
      path             = "${local.src_path}/lambda_authorizer"
      pip_requirements = true
    }
  ]
}

module "get_realms_lambda" {
  source        = "terraform-aws-modules/lambda/aws"
  publish       = true
  function_name = "${local.resource_prefix}-get_realms"
  handler       = "app.lambda_handler"
  runtime       = "python3.11"
  timeout       = 900

  environment_variables = {
    DYNAMODB_TABLE_NAME = local.dynamodb_table_name
  }

  attach_policies    = true
  number_of_policies = 3
  policies = [
    aws_iam_policy.dynamodb_read_write.arn,
    "arn:aws:iam::aws:policy/AWSXrayReadOnlyAccess",
    "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
  ]

  source_path = [
    {
      pip_requirements = "${local.project_root}/production-requirements.txt"
    },
    {
      path             = "${local.src_path}/packages/consent_management_common",
      pip_requirements = true
    },
    {
      path             = "${local.src_path}/services/get_realms"
      pip_requirements = true
    }
  ]

  create_package = !var.is_localstack_deploy
  s3_existing_package = var.is_localstack_deploy ? {
    bucket = "hot-reload"
    # To enable hot reloading, this must be an absolute path
    key = "${abspath(local.project_root)}/build/localstack-hot/services/get_realms"
  } : null
}

module "get_consent_document_versions_lambda" {
  source        = "terraform-aws-modules/lambda/aws"
  publish       = true
  function_name = "${local.resource_prefix}-get_consent_document_versions"
  handler       = "app.lambda_handler"
  runtime       = "python3.11"
  timeout       = 900

  environment_variables = {
    DYNAMODB_TABLE_NAME = local.dynamodb_table_name
  }

  attach_policies    = true
  number_of_policies = 3
  policies = [
    aws_iam_policy.dynamodb_read_write.arn,
    "arn:aws:iam::aws:policy/AWSXrayReadOnlyAccess",
    "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
  ]

  source_path = [
    {
      path             = "${local.src_path}/packages/consent_management_common",
      pip_requirements = true
    },
    {
      path             = "${local.src_path}/services/get_consent_document_versions"
      pip_requirements = true
    }
  ]

  create_package = !var.is_localstack_deploy
  s3_existing_package = var.is_localstack_deploy ? {
    bucket = "hot-reload"
    # To enable hot reloading, this must be an absolute path
    key = "${abspath(local.project_root)}/build/localstack-hot/services/get_consent_document_versions"
  } : null
}

module "create_user_consent_event_lambda" {
  source        = "terraform-aws-modules/lambda/aws"
  publish       = true
  function_name = "${local.resource_prefix}-create_user_consent_event"
  handler       = "app.lambda_handler"
  runtime       = "python3.11"
  timeout       = 900

  environment_variables = {
    DYNAMODB_TABLE_NAME = local.dynamodb_table_name
  }

  attach_policies    = true
  number_of_policies = 3
  policies = [
    aws_iam_policy.dynamodb_read_write.arn,
    "arn:aws:iam::aws:policy/AWSXrayReadOnlyAccess",
    "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
  ]

  source_path = [
    {
      pip_requirements = "${local.project_root}/production-requirements.txt"
    },
    {
      path             = "${local.src_path}/packages/consent_management_common",
      pip_requirements = true
    },
    {
      path             = "${local.src_path}/services/create_user_consent_event"
      pip_requirements = true
    }
  ]

  create_package = !var.is_localstack_deploy
  s3_existing_package = var.is_localstack_deploy ? {
    bucket = "hot-reload"
    # To enable hot reloading, this must be an absolute path
    key = "${abspath(local.project_root)}/build/localstack-hot/services/create_user_consent_event"
  } : null
}

module "get_current_consent_version_lambda" {
  source        = "terraform-aws-modules/lambda/aws"
  publish       = true
  function_name = "${local.resource_prefix}-get-current-consent-version"
  handler       = "app.lambda_handler"
  runtime       = "python3.11"
  timeout       = 900

  environment_variables = {
    DYNAMODB_TABLE_NAME = local.dynamodb_table_name
  }

  attach_policies    = true
  number_of_policies = 3
  policies = [
    aws_iam_policy.dynamodb_read_write.arn,
    "arn:aws:iam::aws:policy/AWSXrayReadOnlyAccess",
    "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
  ]

  source_path = [
    {
      pip_requirements = "${local.project_root}/production-requirements.txt"
    },
    {
      path             = "${local.src_path}/packages/consent_management_common",
      pip_requirements = true
    },
    {
      path             = "${local.src_path}/services/get_current_consent_version"
      pip_requirements = true
    }
  ]

  create_package = !var.is_localstack_deploy
  s3_existing_package = var.is_localstack_deploy ? {
    bucket = "hot-reload"
    # To enable hot reloading, this must be an absolute path
    key = "${abspath(local.project_root)}/build/localstack-hot/services/get_current_consent_version"
  } : null
}

output "api_gateway_base_url" {
  value = aws_api_gateway_stage.api_gateway_deployed_stage_production.invoke_url
}