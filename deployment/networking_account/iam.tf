# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# ---------- automation/networking_account/iam.tf ----------

# ---------- LAMBDA FUNCTION ASSUME POLICY ----------
data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# ---------- ONBOARDING OF NEW SPOKE ACCOUNTS (SQS SUBSCRIPTION) ----------
# Event Bus policy - Allowing Events send by the AWS Organization
resource "aws_cloudwatch_event_bus_policy" "allow_organization" {
  event_bus_name = aws_cloudwatch_event_bus.new_sns_eventbus.name

  policy = data.aws_iam_policy_document.eventbus_policy.json
}

data "aws_iam_policy_document" "eventbus_policy" {
  statement {
    sid       = "AllowOrgAccess"
    effect    = "Allow"
    resources = ["${aws_cloudwatch_event_bus.new_sns_eventbus.arn}"]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions = [
      "events:PutEvents",
      "events:PutRule"
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalOrgID"
      values   = ["${data.aws_organizations_organization.org.id}"]
    }
  }
}

# Lambda function policy (Allowing creating SQS subscriptions)
resource "aws_iam_role" "subs_lambda_role" {
  name               = "SubscriptionLambdaRole"
  path               = "/"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_iam_role_policy_attachment" "subs_lambda_policy_attachment" {
  role       = aws_iam_role.subs_lambda_role.name
  policy_arn = aws_iam_policy.subs_lambda_policy.arn
}

resource "aws_iam_role_policy_attachment" "subs_lambda_managed_policy_attachment" {
  role       = aws_iam_role.subs_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "subs_lambda_policy" {
  name        = "SubscriptionLambdaPolicy"
  path        = "/"
  description = "AWS Lambda permissions to subscribe SNS topics to an SQS queue."

  policy = data.aws_iam_policy_document.subs_lambda_policy.json
}

data "aws_iam_policy_document" "subs_lambda_policy" {
  statement {
    sid       = "AllowResourceRecordSet"
    effect    = "Allow"
    actions   = ["sns:Subscribe"]
    resources = ["*"]
  }
}

# ---------- CREATE ALIAS RECORD (VPC LATTICE DNS INFORMATION) ----------
# SQS queue policy
resource "aws_sqs_queue_policy" "sqs_queue_policy" {
  queue_url = aws_sqs_queue.phz_information_queue.id
  policy    = data.aws_iam_policy_document.sqs_queue_policy.json
}

data "aws_iam_policy_document" "sqs_queue_policy" {
  statement {
    sid       = "allow-sns-topic"
    effect    = "Allow"
    actions   = ["SQS:SendMessage"]
    resources = [aws_sqs_queue.phz_information_queue.arn]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalServiceName"
      values   = ["sns.amazonaws.com"]
    }
  }
}

# Dead-Letter Queue redrive allow policy
resource "aws_sqs_queue_redrive_allow_policy" "queue_redrive_allow_policy" {
  queue_url = aws_sqs_queue.queue_deadletter.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue",
    sourceQueueArns   = [aws_sqs_queue.phz_information_queue.arn]
  })
}

# Lambda function policy (Allowing SQS actions and creation of Route 53 records)
resource "aws_iam_role" "dns_lambda_role" {
  name               = "DNSLambdaRole"
  path               = "/"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_iam_role_policy_attachment" "dns_lambda_policy_attachment" {
  role       = aws_iam_role.dns_lambda_role.name
  policy_arn = aws_iam_policy.dns_lambda_policy.arn
}

resource "aws_iam_role_policy_attachment" "dns_lambda_managed_lamdbabasic_policy_attachment" {
  role       = aws_iam_role.dns_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "dns_lambda_managed_sqsexecution_policy_attachment" {
  role       = aws_iam_role.dns_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole"
}

resource "aws_iam_policy" "dns_lambda_policy" {
  name        = "DNSLambdaPolicy"
  path        = "/"
  description = "AWS Lambda permissions to update records in a Private Hosted Zone."

  policy = data.aws_iam_policy_document.dns_lambda_policy.json
}

data "aws_iam_policy_document" "dns_lambda_policy" {
  statement {
    sid       = "AllowResourceRecordSet"
    effect    = "Allow"
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = ["arn:aws:route53:::hostedzone/${var.phz_id}"]
  }
}