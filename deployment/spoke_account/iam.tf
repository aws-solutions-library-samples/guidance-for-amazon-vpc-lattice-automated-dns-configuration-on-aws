# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# ---------- automation/spoke_account/iam.tf ----------

# ---------- LAMBDA ASSUME ROLE ----------
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

# ---------- SNS TOPIC POLICY ----------
resource "aws_sns_topic_policy" "new_vpc_lattice_service" {
  arn    = aws_sns_topic.new_vpc_lattice_service.arn
  policy = data.aws_iam_policy_document.sns_topic_policy.json
}

data "aws_iam_policy_document" "sns_topic_policy" {
  policy_id = "SNSSQSActionsPolicy"

  statement {
    sid       = "SNSActions"
    effect    = "Allow"
    resources = [aws_sns_topic.new_vpc_lattice_service.arn]

    principals {
      type        = "AWS"
      identifiers = [data.aws_caller_identity.account.account_id]
    }

    actions = [
      "SNS:Subscribe",
      "SNS:SetTopicAttributes",
      "SNS:RemovePermission",
      "SNS:Receive",
      "SNS:Publish",
      "SNS:ListSubscriptionsByTopic",
      "SNS:GetTopicAttributes",
      "SNS:DeleteTopic",
      "SNS:AddPermission",
    ]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceOwner"
      values   = [data.aws_caller_identity.account.account_id]
    }
  }

  statement {
    sid       = "SQSPermissions"
    effect    = "Allow"
    resources = [aws_sns_topic.new_vpc_lattice_service.arn]

    actions = [
      "SNS:Subscribe",
      "SNS:Receive",
    ]

    principals {
      type        = "AWS"
      identifiers = [var.networking_account]
    }

    condition {
      test     = "StringLike"
      variable = "SNS:Endpoint"
      values   = [local.networking_resources.sqs_arn]
    }
  }
}

# ---------- ONBOARDING SNS TOPICS TO NETWORKING SQS QUEUE ----------
# EventBridge role
resource "aws_iam_role" "eventrule_role" {
  name               = "EventRuleRole"
  path               = "/"
  assume_role_policy = data.aws_iam_policy_document.assume_role_eventbridge.json
}

# EventBridge policy
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

resource "aws_iam_role_policy_attachment" "attach_cross_account_policy" {
  role       = aws_iam_role.eventrule_role.name
  policy_arn = aws_iam_policy.rule_role_policy.arn
}

# Lambda function role (Tagging SNS topic)
resource "aws_iam_role" "lambda_tagsns_role" {
  name               = "TagSNSRole"
  path               = "/"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

# Lambda function policies (Tagging SNS topic)
resource "aws_iam_role_policy_attachment" "tagsns_lambda_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.tagsns_lambda_policy.arn
}

resource "aws_iam_role_policy_attachment" "tagsns_lambdabasic_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "tagsns_lambda_policy" {
  name        = "TagSNSLambdaPolicy"
  path        = "/"
  description = "AWS Lambda permissions to tag SNS topics."

  policy = data.aws_iam_policy_document.tagsns_lambda_policy.json
}

data "aws_iam_policy_document" "tagsns_lambda_policy" {
  statement {
    sid       = "AllowSNSTaggin"
    effect    = "Allow"
    actions   = ["sns:*"]
    resources = [aws_sns_topic.new_vpc_lattice_service.arn]
  }
}

# ---------- CATCHING NEW VPC LATTICE SERVICES AND NOTIFYING NETWORKING ACCOUNT ----------
# Lambda function role
resource "aws_iam_role" "lambda_role" {
  name               = "NewVPCLatticeServiceRole"
  path               = "/"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

# Lambda function policies
resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

resource "aws_iam_role_policy_attachment" "lambda_managed_lamdbabasic_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "lambda_policy" {
  name        = "LambdaPolicy"
  path        = "/"
  description = "AWS Lambda permissions to obtain information about a VPC Lattice service and send SNS notifications."

  policy = data.aws_iam_policy_document.lambda_policy.json
}

data "aws_iam_policy_document" "lambda_policy" {
  statement {
    sid       = "AllowVPCLatticeServiceActions"
    effect    = "Allow"
    actions   = ["vpc-lattice:GetService"]
    resources = ["arn:aws:vpc-lattice:${var.aws_region}:${data.aws_caller_identity.account.account_id}:service/*"]
  }

  statement {
    sid       = "AllowSNSPublish"
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = ["${aws_sns_topic.new_vpc_lattice_service.arn}"]
  }
}