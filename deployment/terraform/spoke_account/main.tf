# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# ---------- automation/spoke_account/main.tf ----------

# --------- DATA SOURCES -----------
# AWS Account ID 
data "aws_caller_identity" "account" {}

# ---------- OBTAINING PARAMETERS FROM CENTRAL ACCOUNT ----------
data "aws_ssm_parameter" "networking_resources" {
  name = "arn:aws:ssm:${var.aws_region}:${var.networking_account}:parameter/automation_resources"
}

locals {
  networking_resources = jsondecode(data.aws_ssm_parameter.networking_resources.value)
}

# ---------- CATCHING NEW VPC LATTICE SERVICES AND SENDING INFORMATION TO STEP FUNCTIONS ----------
# EventBridge rule
resource "aws_cloudwatch_event_rule" "vpclattice_newservice_rule" {
  name          = "vpclattice_newservice_rule"
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

# Target Cross-Account Event Bus
resource "aws_cloudwatch_event_target" "vpclattice_newservice_target" {
  rule      = aws_cloudwatch_event_rule.vpclattice_newservice_rule.name
  target_id = "SendToCrossAccountEventBus"
  arn       = local.networking_resources.eventbus_arn
  role_arn  = aws_iam_role.eventrule_role.arn

  dead_letter_config {
    arn = aws_sqs_queue.queue_deadletter.arn
  }
}

# Dead-Letter queue
resource "aws_sqs_queue" "queue_deadletter" {
  name                    = "deadletter-queue"
  sqs_managed_sse_enabled = true
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