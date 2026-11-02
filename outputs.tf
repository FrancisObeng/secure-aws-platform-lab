output "instance_id" {
  description = "EC2 instance ID (use this to connect with SSM)"
  value       = aws_instance.web.id
}

output "vpc_id" {
  value = aws_vpc.main.id
}
