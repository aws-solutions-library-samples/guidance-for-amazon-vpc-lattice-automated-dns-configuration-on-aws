# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# ---------- test/networking_account/main.tf ----------

# ---------- VPC LATTICE SERVICE NETWORK ----------
resource "aws_vpclattice_service_network" "service_network" {
  name      = "service-network"
  auth_type = "NONE"
}

# ---------- AMAZON ROUTE 53 ----------
# Route 53 Profile
resource "awscc_route53profiles_profile" "r53_profile" {
  name = "r53-profile"
}

# Route 53 Private Hosted Zone (and Profile association)
resource "aws_route53_zone" "phz" {
  name = var.private_hosted_zone_name

  vpc {
    vpc_id = aws_vpc.mock_vpc.id
  }
}

resource "awscc_route53profiles_profile_resource_association" "r53_profile_resource_association" {
  name         = "phz-association"
  profile_id   = awscc_route53profiles_profile.r53_profile.id
  resource_arn = aws_route53_zone.phz.arn
}

resource "aws_vpc" "mock_vpc" {
  cidr_block = "10.0.0.0/24"

  tags = {
    Name = "Mock VPC"
  }
}

# ---------- SYSTEMS MANAGER PARAMETER (SERVICE NETWORK & ROUTE 53 PROFILE) ----------
locals {
  networking_account = {
    service_network = aws_vpclattice_service_network.service_network.arn
    r53_profile     = awscc_route53profiles_profile.r53_profile.id
  }
}

# AWS Systems Manager parameter
resource "aws_ssm_parameter" "networking_resources" {
  name  = "test_network_resources"
  type  = "String"
  value = jsonencode(local.networking_account)
  tier  = "Advanced"
}

# ---------- AWS RESOURCES ACCESS MANAGER ----------
# AWS Organization ID
data "aws_organizations_organization" "org" {}

# Resource Share
resource "aws_ram_resource_share" "resource_share" {
  name                      = "test-networking-resources"
  allow_external_principals = false
}

# Principal Association
resource "aws_ram_principal_association" "principal_association" {
  principal          = data.aws_organizations_organization.org.arn
  resource_share_arn = aws_ram_resource_share.resource_share.arn
}

resource "aws_ram_resource_association" "service_network_association" {
  resource_arn       = aws_vpclattice_service_network.service_network.arn
  resource_share_arn = aws_ram_resource_share.resource_share.arn
}

resource "aws_ram_resource_association" "r53_profile_association" {
  resource_arn       = awscc_route53profiles_profile.r53_profile.arn
  resource_share_arn = aws_ram_resource_share.resource_share.arn
}

resource "aws_ram_resource_association" "parameter_association" {
  resource_arn       = aws_ssm_parameter.networking_resources.arn
  resource_share_arn = aws_ram_resource_share.resource_share.arn
}