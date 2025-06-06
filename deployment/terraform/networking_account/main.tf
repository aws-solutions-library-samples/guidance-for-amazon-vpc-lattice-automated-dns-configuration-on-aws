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
    "source" : ["aws.tag"],
    "detail-type" : ["Tag Change on Resource"],
    "detail" : {
        "changed-tag-keys": ["NewService"],
        "service": ["vpc-lattice"],
        "resource-type": ["service"]
    }
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

# ---------- AMAZON DYNAMODB TABLE ----------
resource "aws_dynamodb_table" "vpclattice_dnsautomation" {
  name           = "VPCLattice_DNSAutomation"
  read_capacity  = 5
  write_capacity = 5
  hash_key       = "ServiceArn"

  attribute {
    name = "ServiceArn"
    type = "S"
  }
}

# ---------- STEP FUNCTIONS (UPDATING PRIVATE HOSTED ZONE RECORD) ----------
resource "aws_sfn_state_machine" "sfn_phz" {
  name     = "phz-configuration"
  role_arn = aws_iam_role.sfn_role.arn

  definition = <<EOF
        {
          "Comment": "Guidance for VPC Lattice automated DNS configuration on AWS (SO9532)",
          "StartAt": "ActionType",
          "States": {
            "ActionType": {
              "Type": "Choice",
              "Default": "Pass",
              "Choices": [
                {
                  "Next": "GetService",
                  "Condition": "{% $exists($states.input.detail.tags.NewService) and ($states.input.detail.tags.NewService = \"true\") %}",
                  "Assign": {
                    "ServiceArn": "{% $states.input.resources[0] %}"
                  }
                },
                {
                  "Next": "GetDNSConfiguration",
                  "Condition": "{% 'NewService' in $states.input.detail.'changed-tag-keys' and $not($exists($states.input.detail.tags.NewService)) %}",
                  "Assign": {
                    "ServiceArn": "{% $states.input.resources[0] %}"
                  }
                }
              ],
              "QueryLanguage": "JSONata"
            },
            "GetDNSConfiguration": {
              "Type": "Task",
              "Resource": "arn:aws:states:::dynamodb:getItem",
              "Next": "Choice",
              "QueryLanguage": "JSONata",
              "Arguments": {
                "TableName": "${aws_dynamodb_table.vpclattice_dnsautomation.id}",
                "Key": {
                  "ServiceArn": {
                    "S": "{% $ServiceArn %}"
                  }
                }
              }
            },
            "Choice": {
              "Type": "Choice",
              "Default": "Pass",
              "Choices": [
                {
                  "Next": "DeleteDNSConfiguration",
                  "Condition": "{% $exists($states.input.Item) %}",
                  "Output": {
                    "CustomDomainName": "{% $states.input.Item.CustomDomainName.S %}",
                    "VpcLatticeDomainName": "{% $states.input.Item.VpcLatticeDomainName.S %}",
                    "HostedZoneId": "{% $states.input.Item.HostedZoneId.S %}"
                  }
                }
              ],
              "QueryLanguage": "JSONata"
            },
            "DeleteDNSConfiguration": {
              "Type": "Parallel",
              "Branches": [
                {
                  "StartAt": "ListHostedZoneRecords",
                  "States": {
                    "ListHostedZoneRecords": {
                      "Type": "Task",
                      "Resource": "arn:aws:states:::aws-sdk:route53:listResourceRecordSets",
                      "QueryLanguage": "JSONata",
                      "Arguments": {
                        "HostedZoneId": "{% $states.input.HostedZoneId %}"
                      },
                      "Output": {
                        "Records": "{% $states.result.ResourceRecordSets %}"
                      },
                      "Next": "CheckHostedZoneRecords",
                      "Assign": {
                        "CustomDomainName": "{% $states.input.CustomDomainName %}"
                      }
                    },
                    "CheckHostedZoneRecords": {
                      "Type": "Map",
                      "ItemProcessor": {
                        "ProcessorConfig": {
                          "Mode": "INLINE"
                        },
                        "StartAt": "FoundRecord",
                        "States": {
                          "FoundRecord": {
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
                          "NoAction": {
                            "Type": "Pass",
                            "End": true
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
                  "StartAt": "DeleteItem",
                  "States": {
                    "DeleteItem": {
                      "Type": "Task",
                      "Resource": "arn:aws:states:::dynamodb:deleteItem",
                      "End": true,
                      "QueryLanguage": "JSONata",
                      "Arguments": {
                        "TableName": "${aws_dynamodb_table.vpclattice_dnsautomation.id}",
                        "Key": {
                          "ServiceArn": "{% $ServiceArn %}"
                        }
                      }
                    }
                  }
                }
              ],
              "QueryLanguage": "JSONata",
              "End": true
            },
            "GetService": {
              "Type": "Task",
              "Resource": "arn:aws:states:::aws-sdk:vpclattice:getService",
              "Next": "CustomDNSConfigured",
              "QueryLanguage": "JSONata",
              "Output": {
                "ServiceInformation": "{% $states.result %}",
                "customDomainProvided": "{% $exists($states.result.CustomDomainName) %}"
              },
              "Arguments": {
                "ServiceIdentifier": "{% $ServiceArn %}"
              }
            },
            "CustomDNSConfigured": {
              "Type": "Choice",
              "Default": "Pass",
              "Choices": [
                {
                  "Next": "ServiceCreated",
                  "Condition": "{% $states.input.customDomainProvided %}",
                  "Output": {
                    "CustomDomainName": "{% $states.input.ServiceInformation.CustomDomainName %}",
                    "DnsEntry": "{% $states.input.ServiceInformation.DnsEntry %}"
                  }
                }
              ],
              "QueryLanguage": "JSONata"
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
                                  "HostedZoneId": "{% $states.input.DnsEntry.HostedZoneId %}",
                                  "DnsName": "{% $states.input.DnsEntry.DomainName %}",
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
                                  "HostedZoneId": "{% $states.input.DnsEntry.HostedZoneId %}",
                                  "DnsName": "{% $states.input.DnsEntry.DomainName %}",
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
                  "StartAt": "TrackAliasRecord",
                  "States": {
                    "TrackAliasRecord": {
                      "Type": "Task",
                      "Resource": "arn:aws:states:::dynamodb:putItem",
                      "End": true,
                      "QueryLanguage": "JSONata",
                      "Arguments": {
                        "TableName": "${aws_dynamodb_table.vpclattice_dnsautomation.id}",
                        "Item": {
                          "ServiceArn": {
                            "S": "{% $ServiceArn %}"
                          },
                          "CustomDomainName": {
                            "S": "{% $states.input.CustomDomainName %}"
                          },
                          "VpcLatticeDomainName": {
                            "S": "{% $states.input.DnsEntry.DomainName %}"
                          },
                          "HostedZoneId": {
                            "S": "${var.phz_id}"
                          }
                        }
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