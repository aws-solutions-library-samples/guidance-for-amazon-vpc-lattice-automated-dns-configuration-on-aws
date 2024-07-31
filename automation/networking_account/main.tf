# ---------- root/main.tf ----------

# --------- DATA SOURCES -----------
# Organization ID
data "aws_organizations_organization" "org" {}
# AWS Region
data "aws_region" "current" {}
# AWS Account ID 
data "aws_caller_identity" "account" {}

# ---------- SQS QUEUE ----------
resource "aws_sqs_queue" "mySQS" {
  name = "mySQS"
}

resource "aws_sqs_queue_policy" "sqs_queue_policy" {
  queue_url = aws_sqs_queue.mySQS.id
  policy    = data.aws_iam_policy_document.sqs_queue_policy.json
}

data "aws_iam_policy_document" "sqs_queue_policy" {
  statement {
    sid       = "allow-sns-topic"
    effect    = "Allow"
    actions   = ["SQS:SendMessage"]
    resources = [aws_sqs_queue.mySQS.arn]

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

resource "aws_sqs_queue" "queue_deadletter" {
  name = "deadletter-queue"
}

resource "aws_sqs_queue_redrive_allow_policy" "queue_redrive_allow_policy" {
  queue_url = aws_sqs_queue.queue_deadletter.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue",
    sourceQueueArns   = [aws_sqs_queue.mySQS.arn]
  })
}

# SQS Lambda function invocation
resource "aws_lambda_event_source_mapping" "sqs_lambda_invocation" {
  event_source_arn = aws_sqs_queue.mySQS.arn
  function_name    = aws_lambda_function.dns_lambda.arn
}

# ---------- LAMBDA FUNCTION: UPDATE PHZ WITH ALIAS RECORD ----------
resource "aws_iam_role" "iam_for_lambda" {
  name = "iam_for_lambda"
  path = "/"

  assume_role_policy  = data.aws_iam_policy_document.assume_role.json
  managed_policy_arns = ["arn:aws:iam::aws:policy/AdministratorAccess"]
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

data "archive_file" "dns_lambda" {
  type        = "zip"
  source_file = "${path.module}/../lambda_functions/dns_config.py" # UPDATE TO YOUR PATH
  output_path = "${path.module}/../lambda_functions/dns_lambda.zip" # UPDATE TO YOUR PATH
}

resource "aws_lambda_function" "dns_lambda" {
  filename         = "${path.module}/../lambda_functions/dns_lambda.zip" # UPDATE TO YOUR PATH
  function_name    = "dns_lambda"
  role             = aws_iam_role.iam_for_lambda.arn
  handler          = "dns_config.lambda_handler"
  source_code_hash = data.archive_file.dns_lambda.output_base64sha256
  runtime          = "python3.12"

  environment {
    variables = {
      PHZ_ID = aws_route53_zone.phz.id
    }
  }
}


# -----------  RAM  ---------------
# only the SQS ARN
resource "aws_ssm_parameter" "sqs_arn_param" {
  name  = "sqs_arn_param"
  type  = "String"
  value = aws_sqs_queue.mySQS.arn
  tier  = "Advanced"
}

# association
resource "aws_ram_resource_share" "sqs_share" {
  name                      = "sqs_share"
  allow_external_principals = false
}

resource "aws_ram_principal_association" "organization_association" {
  principal          = data.aws_organizations_organization.org.arn
  resource_share_arn = aws_ram_resource_share.sqs_share.arn
}

resource "aws_ram_resource_association" "queue_association" {
  resource_arn       = aws_ssm_parameter.sqs_arn_param.arn
  resource_share_arn = aws_ram_resource_share.sqs_share.arn
}


# SHARE the custom EventBridge event bus ARN 
resource "aws_ssm_parameter" "eventbus_name_param" {
  name  = "eventbus_name_param"
  type  = "String"
  value = aws_cloudwatch_event_bus.my_event_bus.arn
  tier  = "Advanced"
}

# association
resource "aws_ram_resource_share" "eventbus_share" {
  name                      = "eventbus_share"
  allow_external_principals = false
}

resource "aws_ram_principal_association" "organization_association2" {
  principal          = data.aws_organizations_organization.org.arn
  resource_share_arn = aws_ram_resource_share.eventbus_share.arn
}

resource "aws_ram_resource_association" "eventbus_association" {
  resource_arn       = aws_ssm_parameter.eventbus_name_param.arn
  resource_share_arn = aws_ram_resource_share.eventbus_share.arn
}


# ------ CUSTOM EVENTBRIDGE BUS FOR NEW SNS TOPIC EVENTS --------
# Create a custom EventBridge event bus
resource "aws_cloudwatch_event_bus" "my_event_bus" {
  name = "my_event_bus"
}

# ACCESS POLICY FOR EVENTBRIDGE BUS FROM ORGANIZATION
resource "aws_cloudwatch_event_bus_policy" "allow_organization" {
  event_bus_name = aws_cloudwatch_event_bus.my_event_bus.name

  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowOrgAccess",
      "Effect": "Allow",
      "Principal": {
        "AWS": "*"
      },
      "Action": [
        "events:PutEvents",
        "events:PutRule"
      ],
      "Resource": "${aws_cloudwatch_event_bus.my_event_bus.arn}",
      "Condition": {
        "StringEquals": {
          "aws:PrincipalOrgID": "${data.aws_organizations_organization.org.id}"
        }
      }
    }
  ]
}
POLICY
}

# Create an EventBridge rule to capture new events in an eventbus
resource "aws_cloudwatch_event_rule" "detect_new_events_in_bus" {
  name           = "detect-new-events-in-bus"
  description    = "Captures new events in custom event bus"
  event_bus_name = aws_cloudwatch_event_bus.my_event_bus.name

  # same pattern as spoke's
  event_pattern = <<PATTERN
  {
    "source": ["aws.tag"],
    "detail-type": ["Tag Change on Resource"],
    "detail": {
      "changed-tag-keys": ["NewService"],
      "service": ["sns"]
  }
}
PATTERN
}

# Permission: EventBridge to invoke Lambda function
resource "aws_lambda_permission" "permission_subs_lambda" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.subs_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.detect_new_events_in_bus.arn
}

data "archive_file" "subs_lambda" {
  type        = "zip"
  source_file = "${path.module}/../lambda_functions/subscription.py" # UPDATE TO YOUR PATH
  output_path = "${path.module}/../lambda_functions/subs_lambda.zip" # UPDATE TO YOUR PATH
}

resource "aws_lambda_function" "subs_lambda" {
  filename         = "${path.module}/../lambda_functions/subs_lambda.zip" # UPDATE TO YOUR PATH
  function_name    = "subs_lambda"
  role             = aws_iam_role.iam_for_lambda.arn
  handler          = "subscription.lambda_handler"
  source_code_hash = data.archive_file.subs_lambda.output_base64sha256
  runtime          = "python3.12"

  environment {
    variables = {
      SQS_ARN = aws_sqs_queue.mySQS.arn
    }
  }
}

resource "aws_cloudwatch_event_target" "my_event_target" {
  rule           = aws_cloudwatch_event_rule.detect_new_events_in_bus.name
  target_id      = "SendToLambda"
  arn            = aws_lambda_function.subs_lambda.arn
  event_bus_name = aws_cloudwatch_event_bus.my_event_bus.name
}

