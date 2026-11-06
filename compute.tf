# --- Find the latest Amazon Linux 2023 image (AMI) ---
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# --- IAM role: the "badge" the server wears ---
resource "aws_iam_role" "ec2_ssm" {
  name = "${var.project_name}-ec2-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_ssm" {
  name = "${var.project_name}-ec2-ssm-profile"
  role = aws_iam_role.ec2_ssm.name
}

# --- Security group: the door policy ---
resource "aws_security_group" "web" {
  name        = "${var.project_name}-web-sg"
  description = "Web server SG - no SSH; HTTP from my IP only; outbound HTTPS only"
  vpc_id      = aws_vpc.main.id

  # Still no SSH. The only way in is HTTP, and only from my IP.
  ingress {
    description = "HTTP from my IP only"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  egress {
    description = "HTTPS out for SSM, package updates, GitHub, and Docker Hub"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-web-sg" }
}

# --- The server ---
resource "aws_instance" "web" {
  ami                         = data.aws_ssm_parameter.al2023.value
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.web.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_ssm.name
  associate_public_ip_address = true

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    encrypted   = true
    volume_size = 8
    volume_type = "gp3"
  }

  # Runs once at first boot: install Docker, pull the app from GitHub, build it, run it
  user_data_replace_on_change = true
  user_data                   = <<-EOF
    #!/bin/bash
    set -euxo pipefail
    dnf -y update
    dnf -y install docker git
    systemctl enable --now docker
    git clone https://github.com/FrancisObeng/secure-aws-platform-lab.git /opt/lab
    docker build -t platform-lab /opt/lab/app
    docker run -d --name web --restart unless-stopped -p 80:8080 platform-lab
  EOF

  tags = { Name = "${var.project_name}-web" }
}
