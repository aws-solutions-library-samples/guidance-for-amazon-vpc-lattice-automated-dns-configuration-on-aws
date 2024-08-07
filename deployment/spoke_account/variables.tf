# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# ---------- automation/spoke_account/variables.tf ----------

variable "aws_region" {
  description = "AWS Region to build the automation in the Spoke AWS Account."
  type        = string
}

variable "networking_account" {
  description = "Networking AWS Account ID."
  type        = string
}