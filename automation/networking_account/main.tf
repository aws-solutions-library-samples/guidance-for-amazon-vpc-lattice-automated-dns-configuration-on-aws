# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# ---------- automation/networking_account/main.tf ----------

# --------- DATA SOURCES -----------
# AWS Organization ID
data "aws_organizations_organization" "org" {}
# AWS Account ID 
data "aws_caller_identity" "account" {}

# ---------- SHARING PARAMETERS WITH SPOKE ACCOUNTS ----------
# 1. SQS ARN - so the spoke Accounts can send the messages about the new VPC Lattice services created.
# 2. EventBridge Event Bus ARN - so spoke Accounts can onboard their SNS topics to the central SQS queue
locals {
  networking_account = {
    sqs_arn      = aws_sqs_queue.phz_information_queue.arn
    eventbus_arn = aws_cloudwatch_event_bus.new_sns_eventbus.arn
  }
}

# AWS Systems Manager parameter
resource "aws_ssm_parameter" "automation_resources" {
  name  = "automation_resources"
  type  = "String"
  value = jsonencode(local.networking_account)
  tier  = "Advanced"
}

# AWS RAM resources
resource "aws_ram_resource_share" "resource_share" {
  name                      = "automation_networking_resources"
  allow_external_principals = false
}

resource "aws_ram_principal_association" "organization_association" {
  principal          = data.aws_organizations_organization.org.arn
  resource_share_arn = aws_ram_resource_share.resource_share.arn
}

resource "aws_ram_resource_association" "parameter_association" {
  resource_arn       = aws_ssm_parameter.automation_resources.arn
  resource_share_arn = aws_ram_resource_share.resource_share.arn
}

# ---------- ONBOARDING OF NEW SPOKE ACCOUNTS (SQS SUBSCRIPTION) ----------
# EventBridge event bus
resource "aws_cloudwatch_event_bus" "new_sns_eventbus" {
  name = "new_sns_eventbus"
}

# EventBridge event rule
resource "aws_cloudwatch_event_rule" "new_sns_eventrule" {
  name           = "detect-new-events-in-bus"
  description    = "Captures new events in custom event bus"
  event_bus_name = aws_cloudwatch_event_bus.new_sns_eventbus.name

  # same pattern as spoke's
  event_pattern = <<PATTERN
  {
    "source": ["aws.tag"],
    "detail-type": ["Tag Change on Resource"],
    "detail": {
      "changed-tag-keys": ["NewSNS"],
      "service": ["sns"]
  }
}
PATTERN
}

# EventBridge target (Lamdba function)
resource "aws_cloudwatch_event_target" "event_target" {
  rule           = aws_cloudwatch_event_rule.new_sns_eventrule.name
  target_id      = "SendToLambda"
  arn            = aws_lambda_function.subs_lambda.arn
  event_bus_name = aws_cloudwatch_event_bus.new_sns_eventbus.name
}

# Permission: EventBridge to invoke Lambda function
resource "aws_lambda_permission" "permission_subs_lambda" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.subs_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.new_sns_eventrule.arn
}

# AWS Lambda function (Subscribe spoke SNS to SQS)
data "archive_file" "subs_lambda" {
  type        = "zip"
  source_file = "${path.module}/../lambda_functions/subscription.py"
  output_path = "${path.module}/../lambda_functions/subs_lambda.zip"
}

resource "aws_lambda_function" "subs_lambda" {
  filename         = "${path.module}/../lambda_functions/subs_lambda.zip"
  function_name    = "subs_lambda"
  role             = aws_iam_role.subs_lambda_role.arn
  handler          = "subscription.lambda_handler"
  source_code_hash = data.archive_file.subs_lambda.output_base64sha256
  runtime          = "python3.12"

  environment {
    variables = {
      SQS_ARN = aws_sqs_queue.phz_information_queue.arn
    }
  }
}

# ---------- CREATE ALIAS RECORD (VPC LATTICE DNS INFORMATION) ----------
# SQS Queue - receiving events from the Spoke Accounts when new VPC Lattice services are created
resource "aws_sqs_queue" "phz_information_queue" {
  name = "phz_information_queue"

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.queue_deadletter.arn
    maxReceiveCount     = 3
  })
}

# Dead-Letter queue
resource "aws_sqs_queue" "queue_deadletter" {
  name = "deadletter-queue"
}

# SQS Lambda function invocation
resource "aws_lambda_event_source_mapping" "sqs_lambda_invocation" {
  event_source_arn = aws_sqs_queue.phz_information_queue.arn
  function_name    = aws_lambda_function.dns_lambda.arn
}

# Lambda function (Creating/Updating Route 53 Alias records)
data "archive_file" "dns_lambda" {
  type        = "zip"
  source_file = "${path.module}/../lambda_functions/dns_config.py"
  output_path = "${path.module}/../lambda_functions/dns_lambda.zip"
}

resource "aws_lambda_function" "dns_lambda" {
  filename         = "${path.module}/../lambda_functions/dns_lambda.zip"
  function_name    = "dns_lambda"
  role             = aws_iam_role.dns_lambda_role.arn
  handler          = "dns_config.lambda_handler"
  source_code_hash = data.archive_file.dns_lambda.output_base64sha256
  runtime          = "python3.12"

  environment {
    variables = {
      PHZ_ID = var.phz_id
    }
  }
}