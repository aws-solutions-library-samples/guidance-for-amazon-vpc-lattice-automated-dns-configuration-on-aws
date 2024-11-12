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

# Target Step Functions
resource "aws_cloudwatch_event_target" "vpclattice_newservice_target" {
  rule      = aws_cloudwatch_event_rule.vpclattice_newservice_rule.name
  target_id = "SendToStepFunctions"
  arn       = aws_sfn_state_machine.sfn_vpclattice.arn
  role_arn  = aws_iam_role.eventrule_role.arn
}

# ---------- STEP FUNCTIONS (OBTAINING VPC LATTICE INFORMATION) ----------
resource "aws_sfn_state_machine" "sfn_vpclattice" {
  name     = "vpclattice-information"
  role_arn = aws_iam_role.sfn_role.arn

  definition = <<EOF
{
  "Comment": "A description of my state machine",
  "StartAt": "ActionType",
  "States": {
    "ActionType": {
      "Type": "Choice",
      "Choices": [
        {
          "And": [
            {
              "Variable": "$.detail.tags.NewService",
              "IsPresent": true
            },
            {
              "Variable": "$.detail.tags.NewService",
              "StringEquals": "true"
            }
          ],
          "Next": "GetService"
        },
        {
          "Not": {
            "Variable": "$.detail.tags.NewService",
            "IsPresent": true
          },
          "Next": "PutEventServiceDeleted"
        }
      ],
      "Default": "Pass"
    },
    "Pass": {
      "Type": "Pass",
      "End": true
    },
    "GetService": {
      "Type": "Task",
      "Parameters": {
        "ServiceIdentifier.$": "$.resources[0]"
      },
      "Resource": "arn:aws:states:::aws-sdk:vpclattice:getService",
      "ResultSelector": {
        "ServiceInformation.$": "$"
      },
      "Next": "CustomDNSConfigured"
    },
    "CustomDNSConfigured": {
      "Type": "Choice",
      "Choices": [
        {
          "Variable": "$.ServiceInformation.CustomDomainName",
          "IsPresent": true,
          "Next": "PutEventServiceCreated"
        }
      ],
      "Default": "Pass"
    },
    "PutEventServiceCreated": {
      "Type": "Task",
      "Resource": "arn:aws:states:::aws-sdk:eventbridge:putEvents",
      "Parameters": {
        "Entries": [
          {
            "Detail.$": "$.ServiceInformation",
            "DetailType": "ServiceCreated",
            "EventBusName": "vpclattice_information",
            "Source": "vpclattice_information"
          }
        ]
      },
      "End": true
    },
    "PutEventServiceDeleted": {
      "Type": "Task",
      "Resource": "arn:aws:states:::events:putEvents",
      "Parameters": {
        "Entries": [
          {
            "Detail": {
              "ServiceArn.$": "$.resources[0]"
            },
            "DetailType": "ServiceDeleted",
            "EventBusName": "vpclattice_information",
            "Source": "vpclattice_information"
          }
        ]
      },
      "End": true
    }
  }
}
EOF

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.sfn_vpclattice_loggroup.arn}:*"
    include_execution_data = true
    level                  = "ERROR"
  }
}

# ---------- EVENTBRIDGE BUS ----------
# EventBridge event bus
resource "aws_cloudwatch_event_bus" "vpclattice_information_eventbus" {
  name = "vpclattice_information"
}

# EventBridge rule
resource "aws_cloudwatch_event_rule" "vpclattice_information_rule" {
  name           = "VpcLattice_Information"
  description    = "Captures events send by Step Functions where VPC Lattice services' information is shared."
  event_bus_name = aws_cloudwatch_event_bus.vpclattice_information_eventbus.name

  event_pattern = <<PATTERN
  {
    "source": ["vpclattice_information"]
  }
PATTERN
}

# Target EventBrige event bus (Networking Account) from rule
resource "aws_cloudwatch_event_target" "vpclattice_information_target" {
  rule           = aws_cloudwatch_event_rule.vpclattice_information_rule.name
  target_id      = "SendToCrossAccountEventBus"
  arn            = local.networking_resources.eventbus_arn
  event_bus_name = aws_cloudwatch_event_bus.vpclattice_information_eventbus.name
  role_arn       = aws_iam_role.eventrule_role.arn

  dead_letter_config {
    arn = aws_sqs_queue.queue_deadletter.arn
  }
}

# Dead-Letter queue
resource "aws_sqs_queue" "queue_deadletter" {
  name                    = "deadletter-queue"
  sqs_managed_sse_enabled = true
}

# ---------- VISIBILITY: AMAZON CLOUDWATCH LOGS ----------
# Step Functions state machine
resource "aws_cloudwatch_log_group" "sfn_vpclattice_loggroup" {
  name = "/aws/vendedlogs/states/"
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