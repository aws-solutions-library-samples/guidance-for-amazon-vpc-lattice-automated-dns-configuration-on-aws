# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# ---------- automation/networking_account/variables.tf ----------

variable "aws_region" {
  description = "AWS Region to build the automation in the Networking AWS Account."
  type        = string
}

variable "phz_id" {
  description = "Amazon Route 53 Private Hosted Zone ID."
  type        = string
}