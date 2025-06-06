# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# ---------- automation/networking_account/iam.tf ----------

# ---------- EVENTBRIDGE EVENT BUS (CROSS-ACCOUNT INFORMATION SHARING) ----------
resource "aws_cloudwatch_event_bus_policy" "allow_organization" {
  event_bus_name = aws_cloudwatch_event_bus.cross_account_eventbus.name

  policy = data.aws_iam_policy_document.eventbus_policy.json
}

data "aws_iam_policy_document" "eventbus_policy" {
  statement {
    sid       = "AllowOrgAccess"
    effect    = "Allow"
    resources = [aws_cloudwatch_event_bus.cross_account_eventbus.arn]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions = ["events:PutEvents"]

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalOrgID"
      values   = [data.aws_organizations_organization.org.id]
    }
  }
}

# ---------- EVENTBRIDGE TARGET (PERMISSION TO INVOKE STEP FUNCTIONS) ----------
# IAM Role
resource "aws_iam_role" "event_target_role" {
  name               = "EventTargetRole"
  path               = "/"
  assume_role_policy = data.aws_iam_policy_document.assume_role_event_target.json
}

data "aws_iam_policy_document" "assume_role_event_target" {
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
resource "aws_iam_policy" "event_target_policy" {
  name        = "EventTargetPolicy"
  description = "Allowing Step Functions invocation."
  policy      = data.aws_iam_policy_document.event_target_policy.json
}

data "aws_iam_policy_document" "event_target_policy" {
  statement {
    effect    = "Allow"
    actions   = ["states:StartExecution"]
    resources = [aws_sfn_state_machine.sfn_phz.arn]
  }
}

resource "aws_iam_role_policy_attachment" "attach_event_target_policy" {
  role       = aws_iam_role.event_target_role.name
  policy_arn = aws_iam_policy.event_target_policy.arn
}

# ---------- STEP FUNCTIONS (UPDATING PRIVATE HOSTED ZONE RECORD) ----------
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
    resources = ["*"]
  }
  statement {
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem"
    ]
    resources = [aws_dynamodb_table.vpclattice_dnsautomation.arn]
  }
  statement {
    effect = "Allow"
    actions = [
      "route53:ChangeResourceRecordSets",
      "route53:ChangeTagsForResource",
      "route53:ListTagsForResource",
      "route53:ListResourceRecordSets"
    ]
    resources = ["arn:aws:route53:::hostedzone/${var.phz_id}"]
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