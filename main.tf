# 1. AMI Data Lookup
data "aws_ami" "app_ami" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-202*.*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# 2. VPC Module
module "blog_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.6.1"

  name = "dev"
  cidr = "10.0.0.0/16"

  azs             = ["us-west-2a", "us-west-2b", "us-west-2c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway = true

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}

# 3. Security Group for the Load Balancer
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
  name    = "blog-app-sg"
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

# 6. Application Load Balancer (ALB) Module (Stripped of target configs)
module "blog_alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "9.9.0"

  name    = "blog-alb"
  vpc_id  = module.blog_vpc.vpc_id
  subnets = module.blog_vpc.public_subnets

  security_groups = [module.alb_sg.security_group_id]

  listeners = {
    blog-http = {
      port     = 80
      protocol = "HTTP"
      target_group_arn = aws_lb_target_group.blog.arn
    }
  }

  tags = {
    Environment = "dev"
  }
}

# 7. Standalone Target Group (Safe from module loops)
resource "aws_lb_target_group" "blog" {
  name        = "blog-tg-fixed"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = module.blog_vpc.vpc_id
  target_type = "instance"

  health_check {
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

# 8. Standalone Target Group Attachment
resource "aws_lb_target_group_attachment" "blog" {
  target_group_arn = aws_lb_target_group.blog.arn
  target_id        = aws_instance.blog.id
  port             = 80
}

module "blog_autoscaling" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "9.3.0"

  name = "blog"

  min_size = 1
  max_size = 2

  vpc_zone_identifier = module.blog_vpc.public_subnets

  launch_template_name = "blog"
  security_groups      = [module.blog_sg.security_group_id]
  instance_type        = var.instance_type
  image_id             = data.aws_ami.app_ami.id

  traffic_source_attachments = {
    blog_alb = {
      traffic_source_identifier = aws_lb_target_group.blog.arn
    }
  }
}
