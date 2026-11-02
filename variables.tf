variable "aws_region" {
  description = "AWS region to deploy into (free plan only allows us-east-2)"
  type        = string
  default     = "us-east-2"
}

variable "project_name" {
  description = "Name prefix for all resources"
  type        = string
  default     = "secure-lab"
}

variable "availability_zone" {
  description = "Availability zone for the subnets"
  type        = string
  default     = "us-east-2a"
}
