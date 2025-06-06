# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# ---------- automation/spoke_account/iam.tf ----------

# ---------- EVENTBRIDGE ROLE ----------
# IAM role
resource "aws_iam_role" "eventrule_role" {
  name               = "EventRuleRole"
  path               = "/"
  assume_role_policy = data.aws_iam_policy_document.assume_role_eventbridge.json
}

data "aws_iam_policy_document" "assume_role_eventbridge" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

# IAM policy
resource "aws_iam_policy" "rule_role_policy" {
  name        = "EventBridgeCrossAccountPolicy"
  description = "Allowing Cross-Account Event Bus access."
  policy      = data.aws_iam_policy_document.rule_role_policy.json
}

data "aws_iam_policy_document" "rule_role_policy" {
  statement {
    effect    = "Allow"
    actions   = ["events:PutEvents"]
    resources = [local.networking_resources.eventbus_arn]
  }
}

resource "aws_iam_role_policy_attachment" "attach_cross_account_policy" {
  role       = aws_iam_role.eventrule_role.name
  policy_arn = aws_iam_policy.rule_role_policy.arn
}