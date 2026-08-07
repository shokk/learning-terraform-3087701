# 1. AMI Data Lookup
data "aws_ami" "app_ami" {
  most_recent = true

  filter {
    name   = "name"
    values = [var.ami_filter.name]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners   = [var.ami_filter.owner]

  filter {
    name   = "state"
    values = ["available"]
  }
}

# 2. VPC Module
module "blog_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.6.1"

  name = var.environment.name
  cidr = "${var.environment.network_prefix}.0.0/16"

  azs             = ["us-west-2a", "us-west-2b", "us-west-2c"]
  private_subnets = ["${var.environment.network_prefix}.1.0/24", "${var.environment.network_prefix}.2.0/24", "${var.environment.network_prefix}.3.0/24"]
  public_subnets  = ["${var.environment.network_prefix}.101.0/24", "${var.environment.network_prefix}.102.0/24", "${var.environment.network_prefix}.103.0/24"]

  map_public_ip_on_launch = true

  enable_nat_gateway = true

  tags = {
    Terraform   = "true"
    Environment = var.environment.name
  }
}

module "alb_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.1.0"
  name    = "blog-alb-sg"
  vpc_id  = module.blog_vpc.vpc_id

  ingress_rules       = ["http-80-tcp", "https-443-tcp"]
  ingress_cidr_blocks = ["0.0.0.0/0"]

  egress_rules       = ["all-all"]
  egress_cidr_blocks = ["0.0.0.0/0"]
}

# 4. Security Group for the EC2 Instance
module "blog_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.1.0"
  name    = "blog-app-sg-${var.environment.name}"
  vpc_id  = module.blog_vpc.vpc_id

  ingress_with_source_security_group_id = [
    {
      rule                     = "http-80-tcp"
      source_security_group_id = module.alb_sg.security_group_id
    }
  ]

  egress_rules       = ["all-all"]
  egress_cidr_blocks = ["0.0.0.0/0"]
}

module "blog_alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "10.5.0"

  name    = "blog-alb-${var.environment.name}"
  vpc_id  = module.blog_vpc.vpc_id
  subnets = module.blog_vpc.public_subnets

  security_groups = [module.alb_sg.security_group_id]

  listeners = {
    blog-http = {
      port     = 80
      protocol = "HTTP"
      forward = {
        target_group_key = "blog_tg"
      }
    }
  }

  target_groups = {
    blog_tg = {
      name_prefix = "blog-${var.environment.name}-"
      protocol    = "HTTP"
      port        = 80
      target_type = "instance"

      # 🟢 FIX: Tells the module to skip its internal target attachment loop
      create_attachment = false

      health_check = {
        enabled             = true
        path                = "/"
        port                = "80"
        protocol            = "HTTP"
        interval            = 30
        timeout             = 5
        healthy_threshold   = 3
        unhealthy_threshold = 3
      }
    }
  }

  tags = {
    Environment = var.environment.name
  }
}

module "blog_autoscaling" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "9.3.0"

  name = "blog-${var.environment.name}"

  min_size = var.min_size
  max_size = var.max_size

  vpc_zone_identifier = module.blog_vpc.public_subnets

  launch_template_name = "blog-${var.environment.name}"
  security_groups      = [module.blog_sg.security_group_id]
  instance_type        = var.instance_type
  image_id             = data.aws_ami.app_ami.id

  user_data = base64encode(<<-EOF
              #!/bin/bash
              dnf update -y
              dnf install -y httpd
              systemctl start httpd
              systemctl enable httpd
              echo "<h1>Terraform Learning: Server Live!</h1>" > /var/www/html/index.html
              EOF
  )

  traffic_source_attachments = {
    blog-alb-${var.environment.name} = {
      traffic_source_identifier = module.blog_alb.target_groups["blog_tg"].arn
    }
  }
}
