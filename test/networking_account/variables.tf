# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# ---------- test/networking_account/variables.tf ----------

variable "aws_region" {
  description = "AWS Region."
  type        = string
}

variable "private_hosted_zone_name" {
  description = "Amazon Route 53 Private Hosted Zone name."
  type        = string
}