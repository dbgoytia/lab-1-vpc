# --------------------------------------
# AWS Backend configuration
# --------------------------------------
terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      region = "us-east-1"
    }
  }
  backend "s3" {
    bucket = "691e4876-f921-0542-c9c7-0989c184fe8c-backend"
    key    = "terraform.tfstate"
    region = "us-east-1"
  }
}

# --------------------------------------
# AWS Provider
# --------------------------------------
provider "aws" {
  region = var.region
}

# --------------------------------------
# Networks: VPCs and Subnets
# --------------------------------------

module "vpc-myvpc" {
  source               = "git::https://github.com/dbgoytia/networks-tf"
  region               = "us-east-1"
  vpc_cidr_block       = "10.0.0.0/16"
  azs                  = ["us-east-1a", "us-east-1b"]
  public_subnets_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets      = ["10.0.3.0/24", "10.0.4.0/24"]
  create_natted_subnet = true
}

# --------------------------------------
# Security: Securiy Groups
# --------------------------------------

# Webserver SG
resource "aws_security_group" "webserver_sg" {
  name        = "webserver_sg"
  description = "WebServer security group"
  vpc_id      = module.vpc-myvpc.vpc_id

  ingress {
    description = "Allows inbound HTTPS access from any IPv4 address"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allows inbound SSH access from Bastion Subnet"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [module.vpc-myvpc.public_subnets_cidrs[0]] # Restrict to bastion subnet
  }

  ingress {
    description = "Allows ICMP from Bastion Subnet"
    from_port   = 1
    to_port     = 1
    protocol    = "tcp"
    cidr_blocks = [module.vpc-myvpc.public_subnets_cidrs[0]] # Restrict to bastion subnet
  }

  ingress {
    description = "Allows inbound HTTP access from any IPv4 address"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Bastion SG
resource "aws_security_group" "bastion_sg" {
  name        = "bastion_sg"
  description = "Bastion host security group"
  vpc_id      = module.vpc-myvpc.vpc_id

  ingress {
    description = "Allows inbound HTTPS access from any IPv4 address"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allows inbound HTTP access from any IPv4 address"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# DB Security Group
resource "aws_security_group" "db_sg" {
  name        = "db_sg"
  description = "DB security group"
  vpc_id      = module.vpc-myvpc.vpc_id

  ingress {
    description = "Allow traffic over port 3306"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --------------------------------------
# EC2
# --------------------------------------

resource "aws_key_pair" "key" {
  key_name   = "dgoytia"
  public_key = file("~/.ssh/id_rsa.pub")
}

resource "tls_private_key" "tmp" {
  algorithm = "RSA"
}

resource "aws_key_pair" "user-ssh-key" {
  key_name   = "my-efs-mount-key"
  public_key = tls_private_key.tmp.public_key_openssh
}

# Webserver App
resource "aws_instance" "wordpress-server" {
  ami                         = "ami-04d29b6f966df1537"
  key_name                    = aws_key_pair.key.key_name
  associate_public_ip_address = true
  instance_type               = "t3.micro"
  vpc_security_group_ids      = [aws_security_group.webserver_sg.id]
  subnet_id                   = module.vpc-myvpc.public_subnets_ids[1]
  user_data                   = <<EOF
    #!/bin/bash
    sudo yum install httpd php php-mysql -y
    cd /var/www/html
    wget https://wordpress.org/wordpress-5.1.1.tar.gz
    tar -xzf wordpress-5.1.1.tar.gz
    cp -r wordpress/* /var/www/html/
    rm -rf wordpress
    rm -rf wordpress-5.1.1.tar.gz
    chmod -R 755 wp-content
    chown -R apache:apache wp-content
    service httpd start
    chkconfig httpd on
    EOF
}

# Bastion Host
resource "aws_instance" "bastion-server" {
  ami                         = "ami-04d29b6f966df1537"
  key_name                    = aws_key_pair.key.key_name
  associate_public_ip_address = true
  instance_type               = "t3.micro"
  vpc_security_group_ids      = [aws_security_group.bastion_sg.id]
  subnet_id                   = module.vpc-myvpc.public_subnets_ids[0]
}


# --------------------------------------
# RDS
# --------------------------------------

resource "aws_db_subnet_group" "database" {
  name       = "wpdb-subnet-group"
  subnet_ids = module.vpc-myvpc.public_subnets_ids
}

resource "aws_db_instance" "wpdb" {
  allocated_storage      = 20
  storage_type           = "gp2"
  engine                 = "mysql"
  engine_version         = "5.7"
  instance_class         = "db.t2.micro"
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  name                   = "mydb"
  username               = "foo"
  password               = "foobarbaz"
  parameter_group_name   = "default.mysql5.7"
  db_subnet_group_name   = aws_db_subnet_group.database.name
  skip_final_snapshot    = true
}