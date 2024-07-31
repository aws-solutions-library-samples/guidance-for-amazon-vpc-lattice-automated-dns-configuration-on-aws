# ---------- root/vpclattice_service.tf ----------

# ---------- TEMP: VPC LATTICE SERVICE ----------
data "archive_file" "service_lambda" {
  type        = "zip"
  source_file = "${path.module}/../python/service.py"
  output_path = "${path.module}/../python/service_lambda.zip"

}

resource "aws_lambda_function" "service_lambda" {
  filename         = "${path.module}/../python/service_lambda.zip"
  function_name    = "service_lambda"
  role             = aws_iam_role.iam_for_lambda.arn
  handler          = "service.lambda_handler"
  source_code_hash = data.archive_file.service_lambda.output_base64sha256
  runtime          = "python3.9"

  environment {
    variables = {
      region = var.aws_region
    }
  }
}

# VPC Lattice Service 1
resource "aws_vpclattice_service" "service1" {
  name               = "service1"
  auth_type          = "NONE"
  custom_domain_name = "service1.vpclattice.pablosc.people.aws.dev"
  tags = {
    NewService = "true"
  }
}

resource "aws_vpclattice_listener" "VPCListener" {
  name               = "listener"
  protocol           = "HTTP"
  service_identifier = aws_vpclattice_service.service1.id
  default_action {
    forward {
      target_groups {
        target_group_identifier = aws_vpclattice_target_group.lambda_target.id
      }
    }
  }
}

# VPC Lattice Service Target Lambda function
resource "aws_vpclattice_target_group" "lambda_target" {
  name = aws_vpclattice_service.service1.name
  type = "LAMBDA"
}

resource "aws_lambda_permission" "allow_VPCLattice" { //permission to invoke event_lambda from eventbridge
  statement_id  = "AllowExecutionFromVPCLattice"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.service_lambda.function_name
  principal     = "vpc-lattice.amazonaws.com"
  source_arn    = aws_vpclattice_service.service1.arn
}

resource "aws_vpclattice_target_group_attachment" "attachment" {
  target_group_identifier = aws_vpclattice_target_group.lambda_target.arn

  target {
    id = aws_lambda_function.service_lambda.arn
  }
}

# # VPC Lattice Service 2
# resource "aws_vpclattice_service" "service2" {
#   name               = "service2"
#   auth_type          = "NONE"
#   custom_domain_name = "service2.vpclattice.pablosc.people.aws.dev"
#   tags = {
#     NewService = "true"
#   }
# }

# resource "aws_vpclattice_service_network_service_association" "service2_association" {
#   service_identifier         = aws_vpclattice_service.service2.id
#   service_network_identifier = aws_vpclattice_service_network.service_network.id
# }

# # VPC Lattice Service Target Lambda function
# resource "aws_vpclattice_target_group" "lambda_target2" {
#   name = aws_vpclattice_service.service2.name
#   type = "LAMBDA"
# }


