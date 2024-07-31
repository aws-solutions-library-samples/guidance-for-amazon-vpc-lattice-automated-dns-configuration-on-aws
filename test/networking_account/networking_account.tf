# ---------- root/networking_account.tf ----------

# ---------- VPC LATTICE RESOURCES ----------
# Service Network
resource "aws_vpclattice_service_network" "service_network" {
  name      = "service-network"
  auth_type = "NONE"
}

# VPC Lattice VPC association
resource "aws_vpclattice_service_network_vpc_association" "sn_vpc_association" {
  vpc_identifier             = aws_vpc.consumer_vpc.id
  service_network_identifier = aws_vpclattice_service_network.service_network.id
  security_group_ids         = [aws_security_group.vpclattice_sg.id]
}

# ---------- ROUTE 53 ----------
# Route 53 Profile
resource "awscc_route53profiles_profile" "r53_profile" {
  name = "r53-profile"
}

# Route 53 Private Hosted Zone (and Profile association)
resource "aws_route53_zone" "phz" {
  name = local.phz_domain_name

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

# ---------- RAM SHARE (VPC Lattice service network & Route 53 Profile) ----------
# Resource Share
resource "aws_ram_resource_share" "resource_share" {
  name                      = "networking-resources"
  allow_external_principals = false
}

# Principal Association
resource "aws_ram_principal_association" "principal_association" {
  principal          = data.aws_organizations_organization.org.arn
  resource_share_arn = aws_ram_resource_share.resource_share.arn
}

resource "aws_ram_resource_association" "vpclattice_association" {
  resource_arn       = aws_vpclattice_service_network.service_network.arn
  resource_share_arn = aws_ram_resource_share.resource_share.arn
}

resource "aws_ram_resource_association" "r53_profile_association" {
  resource_arn       = awscc_route53profiles_profile.r53_profile.arn
  resource_share_arn = aws_ram_resource_share.resource_share.arn
}


