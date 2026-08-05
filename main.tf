# 1. NEW: Dedicated Security Group for the Load Balancer
module "alb_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.1.0"
  name    = "blog-alb-sg"
  vpc_id  = module.blog_vpc.vpc_id

  # Open to the public internet
  ingress_rules       = ["http-80-tcp", "https-443-tcp"]
  ingress_cidr_blocks = ["0.0.0.0/0"]

  egress_rules       = ["all-all"]
  egress_cidr_blocks = ["0.0.0.0/0"]
}

# 2. UPDATED: Security Group for the EC2 Instance (Strictly allows traffic from the ALB)
module "blog_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.1.0"
  name    = "blog-app-sg"
  vpc_id  = module.blog_vpc.vpc_id

  # CRITICAL FIX: Only accept HTTP traffic on port 80 if it comes from our ALB security group
  ingress_with_source_security_group_id = [
    {
      rule                     = "http-80-tcp"
      source_security_group_id = module.alb_sg.security_group_id
    }
  ]

  egress_rules       = ["all-all"]
  egress_cidr_blocks = ["0.0.0.0/0"]
}

# 3. FIXED: ALB Module using correct v9+ structure
module "blog_alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "9.9.0"

  name    = "blog-alb"
  vpc_id  = module.blog_vpc.vpc_id
  subnets = module.blog_vpc.public_subnets

  # Use the dedicated ALB security group
  security_groups = [module.alb_sg.security_group_id]

  listeners = {
    blog-http = {
      port     = 80
      protocol = "HTTP"
      # FIX: Correct module map structure for routing traffic to the target group
      forward = {
        target_group_key = "blog_tg"
      }
    }
  }

  target_groups = {
    blog_tg = {
      name_prefix      = "blog-"
      protocol         = "HTTP"
      port             = 80
      target_type      = "instance"
      
      # Health check configuration to monitor your Apache server
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
    Environment = "dev"
  }
}

# 4. UPDATED: Target Group Attachment targeting the module's generated group
resource "aws_lb_target_group_attachment" "blog" {
  # Dynamically pull the ARN created internally by the ALB module
  target_group_arn = module.blog_alb.target_groups["blog_tg"].arn
  target_id        = aws_instance.blog.id
  port             = 80
}

# NOTE: You can safely delete your separate standalone "aws_lb_target_group" "blog" 
# resource block since the ALB module now builds it natively above!
