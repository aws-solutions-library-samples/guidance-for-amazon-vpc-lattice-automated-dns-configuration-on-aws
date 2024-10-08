# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# ---------- automation/spoke_account/main.tf ----------

# --------- DATA SOURCES -----------
# Organization ID
data "aws_organizations_organization" "org" {}
# AWS Account ID 
data "aws_caller_identity" "account" {}

# ---------- OBTAINING PARAMETERS FROM CENTRAL ACCOUNT ----------
data "aws_ssm_parameter" "networking_resources" {
  name = "arn:aws:ssm:${var.aws_region}:${var.networking_account}:parameter/automation_resources"
}

locals {
  networking_resources = jsondecode(data.aws_ssm_parameter.networking_resources.value)
}

# ---------- SNS TOPIC ----------
resource "aws_sns_topic" "new_vpc_lattice_service" {
  name              = "New-VPCLattice-Service"
  kms_master_key_id = "alias/aws/sns"
}

# Lambda function used to tag the SNS Topic (and generate an EventBridge event)
data "archive_file" "tag_sns" {
  type        = "zip"
  source_file = "${path.module}/../lambda_functions/tag_sns.py"
  output_path = "${path.module}/../lambda_functions/tag_sns.zip"
}

resource "aws_lambda_function" "tag_sns" {
  filename         = "${path.module}/../lambda_functions/tag_sns.zip"
  function_name    = "tag_sns"
  role             = aws_iam_role.lambda_role.arn
  handler          = "tag_sns.lambda_handler"
  source_code_hash = data.archive_file.tag_sns.output_base64sha256
  runtime          = "python3.12"

  environment {
    variables = {
      SNS_TOPIC = aws_sns_topic.new_vpc_lattice_service.arn
    }
  }
}

resource "aws_lambda_invocation" "tagsns_invocation" {
  function_name = aws_lambda_function.tag_sns.function_name
  input         = ""

  depends_on = [aws_cloudwatch_event_target.my_busevent_target]
}

# ---------- ONBOARDING SNS TOPICS TO NETWORKING SQS QUEUE ----------
# EventBridge rule
resource "aws_cloudwatch_event_rule" "detect_new_sns_topic" {
  name        = "NewSNSTopic"
  description = "Captures creation of new SNS Topics to be onboarded to the Networking SQS queue."

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

# Target EventBrige event bus (Networking Account) from rule
resource "aws_cloudwatch_event_target" "my_busevent_target" {
  rule      = aws_cloudwatch_event_rule.detect_new_sns_topic.name
  target_id = "SendToEventBus"
  arn       = local.networking_resources.eventbus_arn
  role_arn  = aws_iam_role.eventrule_role.arn
}

# ---------- CATCHING NEW VPC LATTICE SERVICES AND NOTIFYING NETWORKING ACCOUNT ----------
# EventBridge rule
resource "aws_cloudwatch_event_rule" "eventbridge_rule_new_vpclattice_service" {
  name          = "new_service_rule"
  description   = "Captures changes in VPC Lattice service tags."
  event_pattern = <<E0F
    {
    "source" : ["aws.tag"],
    "detail-type" : ["Tag Change on Resource"],
    "detail" : {
        "changed-tag-keys": ["NewService"],
        "service": ["vpc-lattice"],
        "resource-type": ["service"]
    }
  }
E0F
}

# EventBridge target
resource "aws_cloudwatch_event_target" "eventbridge_lambda_trigger" {
  rule      = aws_cloudwatch_event_rule.eventbridge_rule_new_vpclattice_service.name
  target_id = "SendToEventLambda"
  arn       = aws_lambda_function.new_vpclattice_service.arn
}

# Permission: EventBridge to invoke Lambda function
resource "aws_lambda_permission" "permission_eventbridge_lambda" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.new_vpclattice_service.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.eventbridge_rule_new_vpclattice_service.arn
}

# Lambda function (Obtaining DNS information from VPC Lattice service and publish to SNS topic)
data "archive_file" "new_vpclattice_service" {
  type        = "zip"
  source_file = "${path.module}/../lambda_functions/event_curation.py"
  output_path = "${path.module}/../lambda_functions/event_lambda.zip"
}

resource "aws_lambda_function" "new_vpclattice_service" {
  filename         = "${path.module}/../lambda_functions/event_lambda.zip"
  function_name    = "event_lambda"
  role             = aws_iam_role.lambda_role.arn
  handler          = "event_curation.lambda_handler"
  source_code_hash = data.archive_file.new_vpclattice_service.output_base64sha256
  runtime          = "python3.12"

  environment {
    variables = {
      SNS_TOPIC = aws_sns_topic.new_vpc_lattice_service.arn
    }
  }
}

#--------------------------------------------------------------
# Adding guidance solution ID via AWS CloudFormation resource
#--------------------------------------------------------------
resource "aws_cloudformation_stack" "guidance_deployment_metrics" {
  name          = "tracking-stack"
  template_body = <<STACK
    {
        "AWSTemplateFormatVersion": "2010-09-09",
        "Description": "Guidance for VPC Lattice automated DNS configuration on AWS (SO9532)",
        "Resources": {
            "EmptyResource": {
                "Type": "AWS::CloudFormation::WaitConditionHandle"
            }
        }
    }
    STACK
}