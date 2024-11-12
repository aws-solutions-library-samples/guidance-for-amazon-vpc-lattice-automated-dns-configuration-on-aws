# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# ---------- test/consumer_account/variables.tf ----------

variable "aws_region" {
  description = "AWS Region."
  type        = string
}

variable "networking_account" {
  description = "Networking AWS Account ID."
  type        = string
}