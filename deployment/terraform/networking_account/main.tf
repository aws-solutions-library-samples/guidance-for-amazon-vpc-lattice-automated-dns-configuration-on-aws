# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# ---------- automation/networking_account/main.tf ----------

# --------- DATA SOURCES -----------
# AWS Organization ID
data "aws_organizations_organization" "org" {}
# AWS Account ID 
data "aws_caller_identity" "account" {}

# ---------- SHARING PARAMETERS WITH SPOKE ACCOUNTS ----------
# EventBridge Event Bus ARN - so spoke Accounts can send VPC Lattice service information cross-Account
locals {
  networking_account = {
    eventbus_arn = aws_cloudwatch_event_bus.cross_account_eventbus.arn
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

# ---------- EVENTBRIDGE EVENT BUS (CROSS-ACCOUNT INFORMATION SHARING) ----------
# EventBridge event bus
resource "aws_cloudwatch_event_bus" "cross_account_eventbus" {
  name = "cross_account_eventbus"
}

# EventBridge event rule
resource "aws_cloudwatch_event_rule" "cross_account_eventrule" {
  name           = "VpcLattice_Information"
  description    = "Captures events send by Step Functions where VPC Lattice services' information is shared."
  event_bus_name = aws_cloudwatch_event_bus.cross_account_eventbus.name

  event_pattern = <<PATTERN
  {
    "source": ["vpclattice_information"]
  }
PATTERN
}

# EventBridge target (Step Functions)
resource "aws_cloudwatch_event_target" "event_target_stepfunctions" {
  rule           = aws_cloudwatch_event_rule.cross_account_eventrule.name
  target_id      = "SendToStepFunctions"
  arn            = aws_sfn_state_machine.sfn_phz.arn
  event_bus_name = aws_cloudwatch_event_bus.cross_account_eventbus.name
  role_arn       = aws_iam_role.event_target_role.arn


  retry_policy {
    maximum_event_age_in_seconds = 60
    maximum_retry_attempts       = 5
  }

  dead_letter_config {
    arn = aws_sqs_queue.queue_deadletter.arn
  }
}

# Dead-Letter queue
resource "aws_sqs_queue" "queue_deadletter" {
  name                    = "deadletter-queue"
  sqs_managed_sse_enabled = true
}

# ---------- STEP FUNCTIONS (UPDATING PRIVATE HOSTED ZONE RECORD) ----------
resource "aws_sfn_state_machine" "sfn_phz" {
  name     = "phz-configuration"
  role_arn = aws_iam_role.sfn_role.arn

  definition = <<EOF
{
  "Comment": "A description of my state machine",
  "StartAt": "Choice",
  "States": {
    "Choice": {
      "Type": "Choice",
      "Default": "Pass",
      "Choices": [
        {
          "Next": "ServiceCreated",
          "Condition": "{% $states.input.\"detail-type\" = \"ServiceCreated\" %}",
          "Output": {
            "ServiceArn": "{% $states.input.detail.ServiceArn %}",
            "CustomDomainName": "{% $states.input.detail.CustomDomainName %}",
            "VpcLatticeDomainName": "{% $states.input.detail.DnsEntry.DomainName %}",
            "VpcLatticeHostedZone": "{% $states.input.detail.DnsEntry.HostedZoneId %}"
          }
        },
        {
          "Next": "ListTagsForResource",
          "Condition": "{% $states.input.\"detail-type\" = \"ServiceDeleted\" %}",
          "Assign": {
            "ServiceArn": "{% $states.input.detail.ServiceArn %}"
          }
        }
      ],
      "QueryLanguage": "JSONata"
    },
    "ListTagsForResource": {
      "Type": "Task",
      "Resource": "arn:aws:states:::aws-sdk:route53:listTagsForResource",
      "Next": "CheckTags",
      "QueryLanguage": "JSONata",
      "Arguments": {
        "ResourceId": "${var.phz_id}",
        "ResourceType": "hostedzone"
      },
      "Output": {
        "HostedZoneTags": "{% $states.result.ResourceTagSet.Tags %}"
      }
    },
    "CheckTags": {
      "Type": "Map",
      "ItemProcessor": {
        "ProcessorConfig": {
          "Mode": "INLINE"
        },
        "StartAt": "TagFound",
        "States": {
          "TagFound": {
            "Type": "Choice",
            "Default": "DoNothing",
            "Choices": [
              {
                "Next": "ServiceDeleted",
                "Condition": "{% $states.input.Key = $ServiceArn %}",
                "Assign": {
                  "CustomDomainName": "{% $states.input.Value %}"
                }
              }
            ],
            "QueryLanguage": "JSONata"
          },
          "ServiceDeleted": {
            "Type": "Parallel",
            "Branches": [
              {
                "StartAt": "ListResourceRecordSets",
                "States": {
                  "ListResourceRecordSets": {
                    "Type": "Task",
                    "Resource": "arn:aws:states:::aws-sdk:route53:listResourceRecordSets",
                    "Next": "CheckRecords",
                    "QueryLanguage": "JSONata",
                    "Arguments": {
                      "HostedZoneId": "${var.phz_id}"
                    },
                    "Output": {
                      "Records": "{% $states.result.ResourceRecordSets %}"
                    }
                  },
                  "CheckRecords": {
                    "Type": "Map",
                    "ItemProcessor": {
                      "ProcessorConfig": {
                        "Mode": "INLINE"
                      },
                      "StartAt": "RecordFound",
                      "States": {
                        "RecordFound": {
                          "Type": "Choice",
                          "Default": "NoAction",
                          "Choices": [
                            {
                              "Next": "DeleteResourceRecordSet",
                              "Condition": "{% $states.input.Name = $join([$CustomDomainName,'.']) %}"
                            }
                          ],
                          "QueryLanguage": "JSONata"
                        },
                        "DeleteResourceRecordSet": {
                          "Type": "Task",
                          "Resource": "arn:aws:states:::aws-sdk:route53:changeResourceRecordSets",
                          "End": true,
                          "QueryLanguage": "JSONata",
                          "Arguments": {
                            "ChangeBatch": {
                              "Changes": [
                                {
                                  "Action": "DELETE",
                                  "ResourceRecordSet": "{% $states.input %}"
                                }
                              ]
                            },
                            "HostedZoneId": "${var.phz_id}"
                          }
                        },
                        "NoAction": {
                          "Type": "Pass",
                          "End": true,
                          "QueryLanguage": "JSONata"
                        }
                      }
                    },
                    "End": true,
                    "QueryLanguage": "JSONata",
                    "Items": "{% $states.input.Records %}"
                  }
                }
              },
              {
                "StartAt": "DeleteTag",
                "States": {
                  "DeleteTag": {
                    "Type": "Task",
                    "Resource": "arn:aws:states:::aws-sdk:route53:changeTagsForResource",
                    "End": true,
                    "QueryLanguage": "JSONata",
                    "Arguments": {
                      "ResourceId": "${var.phz_id}",
                      "ResourceType": "hostedzone",
                      "RemoveTagKeys": [
                        "{% $states.input.Key %}"
                      ]
                    }
                  }
                }
              }
            ],
            "End": true,
            "QueryLanguage": "JSONata"
          },
          "DoNothing": {
            "Type": "Pass",
            "End": true,
            "QueryLanguage": "JSONata"
          }
        }
      },
      "End": true,
      "QueryLanguage": "JSONata",
      "Items": "{% $states.input.HostedZoneTags %}"
    },
    "Pass": {
      "Type": "Pass",
      "End": true
    },
    "ServiceCreated": {
      "Type": "Parallel",
      "Branches": [
        {
          "StartAt": "ChangeResourceRecordSetsAAAA",
          "States": {
            "ChangeResourceRecordSetsAAAA": {
              "Type": "Task",
              "Resource": "arn:aws:states:::aws-sdk:route53:changeResourceRecordSets",
              "End": true,
              "QueryLanguage": "JSONata",
              "Arguments": {
                "HostedZoneId": "${var.phz_id}",
                "ChangeBatch": {
                  "Changes": [
                    {
                      "Action": "UPSERT",
                      "ResourceRecordSet": {
                        "Name": "{% $states.input.CustomDomainName %}",
                        "Type": "AAAA",
                        "AliasTarget": {
                          "HostedZoneId": "{% $states.input.VpcLatticeHostedZone %}",
                          "DnsName": "{% $states.input.VpcLatticeDomainName %}",
                          "EvaluateTargetHealth": false
                        }
                      }
                    }
                  ]
                }
              }
            }
          }
        },
        {
          "StartAt": "CreateResourceRecordSet",
          "States": {
            "CreateResourceRecordSet": {
              "Type": "Task",
              "Resource": "arn:aws:states:::aws-sdk:route53:changeResourceRecordSets",
              "End": true,
              "QueryLanguage": "JSONata",
              "Arguments": {
                "HostedZoneId": "${var.phz_id}",
                "ChangeBatch": {
                  "Changes": [
                    {
                      "Action": "UPSERT",
                      "ResourceRecordSet": {
                        "Name": "{% $states.input.CustomDomainName %}",
                        "Type": "A",
                        "AliasTarget": {
                          "HostedZoneId": "{% $states.input.VpcLatticeHostedZone %}",
                          "DnsName": "{% $states.input.VpcLatticeDomainName %}",
                          "EvaluateTargetHealth": false
                        }
                      }
                    }
                  ]
                }
              }
            }
          }
        },
        {
          "StartAt": "CreateTag",
          "States": {
            "CreateTag": {
              "Type": "Task",
              "Resource": "arn:aws:states:::aws-sdk:route53:changeTagsForResource",
              "End": true,
              "QueryLanguage": "JSONata",
              "Arguments": {
                "ResourceId": "${var.phz_id}",
                "ResourceType": "hostedzone",
                "AddTags": [
                  {
                    "Key": "{% $states.input.ServiceArn %}",
                    "Value": "{% $states.input.CustomDomainName %}"
                  }
                ]
              }
            }
          }
        }
      ],
      "End": true,
      "QueryLanguage": "JSONata"
    }
  }
}
EOF

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.sfn_phzconfiguration_loggroup.arn}:*"
    include_execution_data = true
    level                  = "ERROR"
  }
}

# ---------- VISIBILITY: AMAZON CLOUDWATCH LOGS ----------
# Step Functions state machine
resource "aws_cloudwatch_log_group" "sfn_phzconfiguration_loggroup" {
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