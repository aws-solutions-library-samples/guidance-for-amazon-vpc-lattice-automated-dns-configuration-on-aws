# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# ---------- test/consumer_account/main.tf ----------

# ---------- OBTAINING NETWORKING RESOURCES ----------
data "aws_ssm_parameter" "networking_resources" {
  name = "arn:aws:ssm:${var.aws_region}:${var.networking_account}:parameter/test_network_resources"
}

locals {
  networking_resources = jsondecode(data.aws_ssm_parameter.networking_resources.value)
}

# ---------- CONSUMER VPC ----------
module "vpc" {
  source  = "aws-ia/vpc/aws"
  version = "4.4.2"

  name       = "consumer_vpc"
  cidr_block = "10.0.0.0/24"
  az_count   = 2

  vpc_lattice = {
    service_network_identifier = local.networking_resources.service_network
  }

  subnets = {
    workload = { netmask = 28 }
    endpoints = { netmask = 28 }
  }
}

# ---------- AMAZON ROUTE 53 PROFILE VPC ASSOCATION ----------
resource "awscc_route53profiles_profile_association" "r53_profile_vpc_association" {
  name         = "vpc-association"
  profile_id   = local.networking_resources.r53_profile
  resource_id = module.vpc.vpc_attributes.id
}

# ---------- AMAZON EC2 INSTANCE ----------
# EC2 instance security group
resource "aws_security_group" "instance_sg" {
  name        = "instance-security-group"
  description = "EC2 Instance Security Group"
  vpc_id      = module.vpc.vpc_attributes.id
}

resource "aws_vpc_security_group_ingress_rule" "allowing_ingress_eic" {
  security_group_id = aws_security_group.instance_sg.id

  from_port                    = 22
  to_port                      = 22
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.eic_sg.id
}

resource "aws_vpc_security_group_egress_rule" "allowing_egress_any" {
  security_group_id = aws_security_group.instance_sg.id

  ip_protocol = "-1"
  cidr_ipv4   = "0.0.0.0/0"
}

# EC2 Instance Connect endpoint security group 
resource "aws_security_group" "eic_sg" {
  name        = "eic-security-group"
  description = "EC2 Instance Connect Security Group"
  vpc_id      = module.vpc.vpc_attributes.id
}

resource "aws_vpc_security_group_egress_rule" "allowing_egress_ec2_instances" {
  security_group_id = aws_security_group.eic_sg.id

  from_port                    = 22
  to_port                      = 22
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.instance_sg.id
}

# Data resource to determine the latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

# EC2 instance
resource "aws_instance" "ec2_instance" {
  ami                         = data.aws_ami.amazon_linux.id
  associate_public_ip_address = false
  instance_type               = "t2.micro"
  vpc_security_group_ids      = [aws_security_group.instance_sg.id]
  subnet_id                   = values({ for k, v in module.vpc.private_subnet_attributes_by_az : split("/", k)[1] => v.id if split("/", k)[0] == "workload" })[0]

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    encrypted = true
  }

  tags = {
    Name = "consumer-instance"
  }
}

# EC2 Instance Connect endpoint
resource "aws_ec2_instance_connect_endpoint" "eic_endpoint" {
  subnet_id          = values({ for k, v in module.vpc.private_subnet_attributes_by_az : split("/", k)[1] => v.id if split("/", k)[0] == "endpoints" })[0]
  preserve_client_ip = false
  security_group_ids = [aws_security_group.eic_sg.id]
}