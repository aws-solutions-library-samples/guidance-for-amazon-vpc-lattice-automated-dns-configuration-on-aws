# ---------- root/main.tf ----------

# --------- DATA SOURCES -----------
# Organization ID
data "aws_organizations_organization" "org" {}
# AWS Account ID 
data "aws_caller_identity" "account" {}
# AWS Region
data "aws_region" "current" {}

# ---------- EVENTBRIDGE RULE: VPC LATTICE SERVICE TAGS ----------
# EventBridge Rule and Lambda target
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

resource "aws_cloudwatch_event_target" "eventbridge_lambda_trigger" {
  rule      = aws_cloudwatch_event_rule.eventbridge_rule_new_vpclattice_service.name
  target_id = "SendToEventLambda"
  arn       = aws_lambda_function.lambda_function_new_vpclattice_service.arn
}

# Permission: EventBridge to invoke Lambda function
resource "aws_lambda_permission" "permission_eventbridge_lambda" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_function_new_vpclattice_service.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.eventbridge_rule_new_vpclattice_service.arn
}

# ---------- LAMBDA FUNCTION: OBTAINING VPC LATTICE SERVICE INFORMATION ----------
data "archive_file" "lambda_function_new_vpclattice_service" {
  type        = "zip"
  source_file = "${path.module}/../lambda_functions/event_curation.py" # UPDATE TO YOUR PATH
  output_path = "${path.module}/../lambda_functions/event_lambda.zip" # UPDATE TO YOUR PATH
}

resource "aws_lambda_function" "lambda_function_new_vpclattice_service" {
  filename         = "${path.module}/../lambda_functions/event_lambda.zip" # UPDATE TO YOUR PATH
  function_name    = "event_lambda"
  role             = aws_iam_role.iam_for_lambda.arn
  handler          = "event_curation.lambda_handler"
  source_code_hash = data.archive_file.lambda_function_new_vpclattice_service.output_base64sha256
  runtime          = "python3.12"

  environment {
    variables = {
      SNS_TOPIC = aws_sns_topic.new_vpc_lattice_service.arn
    }
  }
}

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

resource "aws_iam_role" "iam_for_lambda" {
  name = "iam_for_lambda"
  path = "/"

  assume_role_policy  = data.aws_iam_policy_document.assume_role.json
  managed_policy_arns = ["arn:aws:iam::aws:policy/AdministratorAccess"]
}

data "aws_ssm_parameter" "sqs_arn_param" {
  name = "arn:aws:ssm:eu-west-1:${var.networking_account}:parameter/sqs_arn_param"
}

# ---------- SNS TOPIC: NEW VPC LATTICE SERVICE ----------
resource "aws_sns_topic" "new_vpc_lattice_service" {
  name = "New-VPCLattice-Service"
  tags = {
    NewSNS = "true"
  }
}

resource "aws_sns_topic_policy" "new_vpc_lattice_service" {
  arn    = aws_sns_topic.new_vpc_lattice_service.arn
  policy = data.aws_iam_policy_document.sns_topic_policy.json
}

data "aws_iam_policy_document" "sns_topic_policy" {
  policy_id = "sns_actions_policy"

  statement {
    sid    = "sns_actions_account"
    effect = "Allow"
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
    resources = [aws_sns_topic.new_vpc_lattice_service.arn]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceOwner"
      values   = [data.aws_caller_identity.account.account_id]
    }
  }

  statement {
    sid    = "sns_sqs_permissions"
    effect = "Allow"
    actions = [
      "SNS:Subscribe",
      "SNS:Receive",
    ]
    resources = [aws_sns_topic.new_vpc_lattice_service.arn]

    principals {
      type        = "AWS"
      identifiers = ["590183737881"]
    }

    condition {
      test     = "StringLike"
      variable = "SNS:Endpoint"
      values   = [data.aws_ssm_parameter.sqs_arn_param.value]
    }
  }
}

# ------------ EVENTBRIDGE RULE TAG ON NEW SNS TOPIC ---------------
data "aws_ssm_parameter" "eventbus_name_param" {
  name = "arn:aws:ssm:eu-west-1:${var.networking_account}:parameter/eventbus_name_param"
}

resource "aws_cloudwatch_event_rule" "detect_new_sns_topic" {
  name        = "detect-new-sns-topic"
  description = "Captures creation of new SNS topics"

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

resource "aws_iam_policy" "rule_role_policy" {
  name        = "eventbridge-crossAccount-policy"
  description = "Allowing Cross-Account Event Bus access."
  policy      = data.aws_iam_policy_document.rule_role_policy.json
}

data "aws_iam_policy_document" "rule_role_policy" {
  statement {
    effect    = "Allow"
    actions   = ["events:PutEvents"]
    resources = [data.aws_ssm_parameter.eventbus_name_param.value]
  }
}

resource "aws_iam_role" "iam_for_rule" {
  name               = "iam_for_rule"
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

resource "aws_iam_role_policy_attachment" "attach_cross_account_policy" {
  role       = aws_iam_role.iam_for_rule.name
  policy_arn = aws_iam_policy.rule_role_policy.arn
}

# Target EventBrige event bus from rule
resource "aws_cloudwatch_event_target" "my_busevent_target" {
  rule      = aws_cloudwatch_event_rule.detect_new_sns_topic.name
  target_id = "SendToEventBus"
  arn       = data.aws_ssm_parameter.eventbus_name_param.value
  role_arn  = aws_iam_role.iam_for_rule.arn
}
