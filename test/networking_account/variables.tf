# ---------- root/variables.tf ----------

variable "aws_region" {
  description = "AWS Region."
  type        = string

  default = "eu-west-1"
}

variable "consumer_vpc" {
  description = "Consumer VPC Information."
  type        = any

  default = {
    cidr_block = "10.0.0.0/24"
    workload_subnet_cidrs = {
      eu-west-1a = "10.0.0.0/28"
      eu-west-1b = "10.0.0.16/28"
    }
    endpoint_subnet_cidrs = {
      eu-west-1a = "10.0.0.32/28"
      eu-west-1b = "10.0.0.48/28"
    }
  }
}