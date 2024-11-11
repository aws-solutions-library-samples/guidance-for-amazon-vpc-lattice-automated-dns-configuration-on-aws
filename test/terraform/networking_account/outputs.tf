# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# ---------- test/networking_account/outputs.tf ----------

output "phz_id" {
  description = "Private Hosted Zone ID."
  value       = aws_route53_zone.phz.id
}