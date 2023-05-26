#creating VPC

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  instance_tenancy     = "default"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "${var.project_name}-${var.project_environment}"
  }
}

#creating igw

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-${var.project_environment}"
  }
}

#creating public subnets

resource "aws_subnet" "publicsubnets" {
  count                   = 3
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 3, count.index)
  availability_zone       = data.aws_availability_zones.azs.names["${count.index}"]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-${var.project_environment}-public${count.index + 1}"
  }

}



#creating private subnets
resource "aws_subnet" "privatesubnets" {
  count                   = 3
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 3, "${count.index + 3}")
  availability_zone       = data.aws_availability_zones.azs.names["${count.index}"]
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project_name}-${var.project_environment}-private${count.index + 1}"
  }

}


#creating public route table

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }


  tags = {
    Name = "${var.project_name}-${var.project_environment}-public"
  }
}



#public route table assosiation

resource "aws_route_table_association" "publics" {
  count          = 3
  subnet_id      = aws_subnet.publicsubnets["${count.index}"].id
  route_table_id = aws_route_table.public.id
}


#creating private routetable

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }


  tags = {
    Name = "${var.project_name}-${var.project_environment}-private"
  }
}


#private route table assosiation

resource "aws_route_table_association" "privates" {
  count          = 3
  subnet_id      = aws_subnet.privatesubnets["${count.index}"].id
  route_table_id = aws_route_table.private.id
}

#eip for nat gw

resource "aws_eip" "nat" {
  vpc = true
  tags = {
    Name = "${var.project_name}-${var.project_environment}-nat"
  }

}

#eip for frontend instance

resource "aws_eip" "frontend" {
  instance = aws_instance.frontend.id
  vpc      = true

  tags = {
    Name = "${var.project_name}-${var.project_environment}"
  }
}

#creating nat gateway

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.publicsubnets[0].id

  tags = {
    Name = "${var.project_name}-${var.project_environment}"
  }
  depends_on = [aws_internet_gateway.igw]
}


#creating keypair and downloading to local end

resource "tls_private_key" "mykey" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "mykey" {
  key_name   = "${var.project_name}_${var.project_environment}" # Create "myKey" to AWS
  public_key = tls_private_key.mykey.public_key_openssh
}
resource "local_file" "mykey" {
  filename        = "${var.project_name}-${var.project_environment}.pem"
  content         = tls_private_key.mykey.private_key_pem
  file_permission = "400"
}


#creating sg for bastion server

resource "aws_security_group" "bastion" {
  name_prefix = "${var.project_name}-${var.project_environment}-bastion-"
  description = "Allow SSH from myIP"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }



  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.project_environment}-bastion"

  }
  lifecycle {

    create_before_destroy = true
  }
}

#creating sg for frontend server

resource "aws_security_group" "frontend" {
  name_prefix = "${var.project_name}-${var.project_environment}-frontend-"
  description = "Allow HTTPS&HTTP from all and SSH from bastion"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]

  }

  ingress {
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }


  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.project_environment}-frontend"

  }
  lifecycle {

    create_before_destroy = true
  }
}


#creating sg for rds server

resource "aws_security_group" "backend" {
  name_prefix = "${var.project_name}-${var.project_environment}-backend-"
  description = "Allow SSH from myIP"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.frontend.id]
  }


  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.project_environment}-backend"

  }
  lifecycle {

    create_before_destroy = true
  }
}



#creating webserver instance
resource "aws_instance" "frontend" {

  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.mykey.key_name
  vpc_security_group_ids = [aws_security_group.frontend.id]
  user_data              = file("frontend.sh")
  subnet_id              = aws_subnet.publicsubnets[0].id

  tags = {
    Name = "${var.project_name}-${var.project_environment}-frontend"
  }


}



#creating bastion instance
resource "aws_instance" "bastion" {

  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.mykey.key_name
  vpc_security_group_ids = [aws_security_group.bastion.id]
  subnet_id              = aws_subnet.publicsubnets[1].id
  tags = {
    Name = "${var.project_name}-${var.project_environment}-bastion"
  }


}


## create rds

resource "aws_db_subnet_group" "subnet_rds" {
  name = "rds_subnet"
  subnet_ids = [
    aws_subnet.privatesubnets[0].id,
    aws_subnet.privatesubnets[1].id
  ]
}

resource "aws_db_instance" "rds" {
  engine                 = "mariadb"
  instance_class         = "db.t2.micro"
  allocated_storage      = 10
  storage_type           = "gp2"
  identifier             = "wordpress-db"
  username               = "wp_user"
  password               = "wpuser_pass"
  db_subnet_group_name   = aws_db_subnet_group.subnet_rds.name
  vpc_security_group_ids = [aws_security_group.backend.id]
}


#pointing blog.ashna.online to eip

resource "aws_route53_record" "blog" {
  zone_id = data.aws_route53_zone.myzone.id
  name    = "blog"
  type    = "A"
  ttl     = 300
  records = [aws_eip.frontend.public_ip]
}


#creating a private zone ashna.local
resource "aws_route53_zone" "private" {
  name = "ashna.local"

  vpc {
    vpc_id = aws_vpc.main.id
  }
}



#pointing bastion.ashna.local to bastion's private ip

resource "aws_route53_record" "bastion" {
  zone_id = aws_route53_zone.private.zone_id
  name    = "bastion"
  type    = "A"
  ttl     = 300
  records = [aws_instance.bastion.private_ip]
}



#pointing backend.ashna.local to RDS address

resource "aws_route53_record" "backend" {
  zone_id = aws_route53_zone.private.zone_id
  name    = "backend"
  type    = "CNAME"
  ttl     = 300
  records = [aws_db_instance.rds.address]
}



#pointing frontend.ashna.local to frontend's private ip

resource "aws_route53_record" "frontend" {
  zone_id = aws_route53_zone.private.zone_id
  name    = "frontend"
  type    = "A"
  ttl     = 300
  records = [aws_instance.frontend.private_ip]
}

