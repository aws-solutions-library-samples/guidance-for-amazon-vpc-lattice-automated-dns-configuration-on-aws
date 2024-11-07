# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# ---------- automation/spoke_account/iam.tf ----------

# ---------- STEP FUNCTIONS (OBTAINING VPC LATTICE INFORMATION) ----------
# IAM Role
resource "aws_iam_role" "sfn_role" {
  name               = "StepFunctionsRole"
  path               = "/"
  assume_role_policy = data.aws_iam_policy_document.assume_role_sfn.json
}

data "aws_iam_policy_document" "assume_role_sfn" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

# IAM policy
resource "aws_iam_policy" "sfn_policy" {
  name        = "StepFunctionsPolicy"
  description = "Allowing Step Functions actions."
  policy      = data.aws_iam_policy_document.sfn_policy.json
}

data "aws_iam_policy_document" "sfn_policy" {
  statement {
    effect    = "Allow"
    actions   = ["vpc-lattice:GetService"]
    resources = ["arn:aws:vpc-lattice:${var.aws_region}:${data.aws_caller_identity.account.id}:service/*"]
  }
  statement {
    effect    = "Allow"
    actions   = ["events:PutEvents"]
    resources = [aws_cloudwatch_event_bus.vpclattice_information_eventbus.arn]
  }
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogDelivery",
      "logs:CreateLogStream",
      "logs:GetLogDelivery",
      "logs:UpdateLogDelivery",
      "logs:DeleteLogDelivery",
      "logs:ListLogDeliveries",
      "logs:PutLogEvents",
      "logs:PutResourcePolicy",
      "logs:DescribeResourcePolicies",
      "logs:DescribeLogGroups"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy_attachment" "attach_sfn_policy" {
  role       = aws_iam_role.sfn_role.name
  policy_arn = aws_iam_policy.sfn_policy.arn
}

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
  statement {
    effect    = "Allow"
    actions   = ["states:StartExecution"]
    resources = [aws_sfn_state_machine.sfn_vpclattice.arn]
  }
}

resource "aws_iam_role_policy_attachment" "attach_cross_account_policy" {
  role       = aws_iam_role.eventrule_role.name
  policy_arn = aws_iam_policy.rule_role_policy.arn
}