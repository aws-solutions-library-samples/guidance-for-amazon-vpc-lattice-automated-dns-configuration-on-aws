# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# ---------- test/provider_account/main.tf ----------

# ---------- OBTAINING NETWORKING RESOURCES ----------
data "aws_ssm_parameter" "networking_resources" {
  name = "arn:aws:ssm:${var.aws_region}:${var.networking_account}:parameter/test_network_resources"
}

locals {
  networking_resources = jsondecode(data.aws_ssm_parameter.networking_resources.value)
}

# ---------- VPC LATTICE SERVICE ----------
module "vpc_lattice_service" {
  source  = "aws-ia/amazon-vpc-lattice-module/aws"
  version = "0.2.0"

  service_network = {
    identifier = local.networking_resources.service_network
  }

  services = {
    lambda = {
      name               = "lambda-service"
      auth_type          = "NONE"
      custom_domain_name = var.custom_domain_name

      listeners = {
        http = {
          port     = 80
          protocol = "HTTP"
          default_action_forward = {
            target_groups = {
              lambdatarget = { weight = 100 }
            }
          }
        }
      }
    }
  }

  target_groups = {
    lambdatarget = {
      type = "LAMBDA"
      targets = {
        lambda_function = { id = aws_lambda_function.service_lambda.arn }
      }
    }
  }

  tags = {
    NewService = true
  }
}

# ---------- LAMBDA FUNCTION ----------
data "archive_file" "service_lambda" {
  type        = "zip"
  source_file = "${path.module}/service.py"
  output_path = "${path.module}/service_lambda.zip"

}

resource "aws_lambda_function" "service_lambda" {
  filename         = "${path.module}/service_lambda.zip"
  function_name    = "service_lambda"
  role             = aws_iam_role.lambda_role.arn
  handler          = "service.lambda_handler"
  source_code_hash = data.archive_file.service_lambda.output_base64sha256
  runtime          = "python3.12"

  environment {
    variables = {
      region = var.aws_region
    }
  }
}

# IAM Role & Policy
# Lambda function policy (Allowing creating SQS subscriptions)
resource "aws_iam_role" "lambda_role" {
  name               = "ProviderLambdaRole"
  path               = "/"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role_policy_attachment" "lambda_managed_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}