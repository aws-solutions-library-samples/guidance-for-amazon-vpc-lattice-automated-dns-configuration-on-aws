# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# ---------- test/provider_account/variables.tf ----------

variable "aws_region" {
  description = "AWS Region."
  type        = string
}

variable "networking_account" {
  description = "Networking AWS Account ID."
  type        = string
}

variable "custom_domain_name" {
  description = "VPC Lattice service's custom domain name."
  type        = string
}