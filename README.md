### Description

AWS Route 53 Private DNS Zones can be used to improve the reliability and ease of connection within a Virtual Private Cloud (VPC).With Route 53 Private DNS Zones, you can create a private namespace that can be accessed only from within your VPC.This allows you to resolve domain names to private IP addresses within your VPC, providing a reliable and secure way to access resources.Instead of using private IP addresses directly, you can configure Route 53 to associate custom domain names (hostnames) with those resources. This can make it easier to manage and access your resources by using more memorable and meaningful names.
 
To set this up, you would typically create a private hosted zone in Route 53 and configure the necessary DNS records to associate your custom domain names with the private IP addresses of your resources within the VPC.By using private hostnames instead of private IP addresses, you can also abstract the underlying infrastructure and easily update the IP addresses of your resources without affecting the clients that use the hostnames

**Here I'm going to create a high availability WordPress application using a frontend, bastion, and RDS server where each instance connects through private hostnames.**

**Here's a general architecture you can follow:**

- Frontend Instances: This instance will handle the web traffic and serve the WordPress content. You can configure the instances to connect to the RDS database using the private hostname of the RDS instance.

- Bastion Host: Create a bastion host (a jump server) within your VPC. This host will act as an entry point to securely access your private instances. You can use SSH to connect to the bastion host and then connect from there to the frontend instances using their private hostnames.

- RDS Server: Deploy your WordPress database using Amazon RDS. Configure the RDS instance to use a private hostname, and configure the security group to allow incoming connections from the frontend instances.

- Create a **Route53 Private DNS zone** to point the private IP addresses to hostnames.

By using private hostnames to connect the instances, you ensure that the communication between the frontend instances and the RDS database remains within the VPC and does not traverse the public internet. This adds an extra layer of security and can improve the performance of your application.


### Let's Get started:

### Step 1 - Create VPC,Subnets,Routetables,NAT GW & IGW

><b> Create provider.tf</b>

```
provider "aws" {
  region     = "ap-south-1"
  access_key = "***********"
  secret_key = "***********************"

  default_tags {
    tags = {
      "Project" = var.project_name
      "Env"     = var.project_environment
    }
  }
}
```


><b> Define Datasourcesn datasources.tf</b>

```
data "aws_availability_zones" "azs" {
  state = "available"
}

data "aws_route53_zone" "myzone" {
  name         = "ashna.online"
  private_zone = false
}

```
> <b>Resource code definitionin main.tf</b>

```
-------------------------------------------------------------------
 Vpc Creation
-------------------------------------------------------------------

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  instance_tenancy     = "default"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "${var.project_name}-${var.project_environment}"
  }
}a

-------------------------------------------------------------------
 Creating igw
-------------------------------------------------------------------

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-${var.project_environment}"
  }
}

-------------------------------------------------------------------
Creating public subnets
-------------------------------------------------------------------

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

-------------------------------------------------------------------
Creating private subnets
-------------------------------------------------------------------

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

-------------------------------------------------------------------
Creating public route table
-------------------------------------------------------------------

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

-------------------------------------------------------------------
Public route table assosiation
-------------------------------------------------------------------

resource "aws_route_table_association" "publics" {
  count          = 3
  subnet_id      = aws_subnet.publicsubnets["${count.index}"].id
  route_table_id = aws_route_table.public.id
}

-------------------------------------------------------------------
Creating private routetable
-------------------------------------------------------------------

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

-------------------------------------------------------------------
Private route table assosiation
-------------------------------------------------------------------

resource "aws_route_table_association" "privates" {
  count          = 3
  subnet_id      = aws_subnet.privatesubnets["${count.index}"].id
  route_table_id = aws_route_table.private.id
}

-------------------------------------------------------------------
eip for nat gw
-------------------------------------------------------------------

resource "aws_eip" "nat" {
  vpc = true
  tags = {
    Name = "${var.project_name}-${var.project_environment}-nat"
  }

}

-------------------------------------------------------------------
eip for frontend instance
-------------------------------------------------------------------

resource "aws_eip" "frontend" {
  instance = aws_instance.frontend.id
  vpc      = true

  tags = {
    Name = "${var.project_name}-${var.project_environment}"
  }
}

-------------------------------------------------------------------
Creating nat gateway
-------------------------------------------------------------------

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.publicsubnets[0].id

  tags = {
    Name = "${var.project_name}-${var.project_environment}"
  }
  depends_on = [aws_internet_gateway.igw]
}
```
### Step 2 - Create keypair and SG for each instances

```
-------------------------------------------------------------------
Creating keypair and downloading to local end
-------------------------------------------------------------------

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

-------------------------------------------------------------------
Creating sg for bastion server
-------------------------------------------------------------------

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
-------------------------------------------------------------------
Creating sg for frontend server
-------------------------------------------------------------------

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

-------------------------------------------------------------------
Creating sg for AWS RDS
-------------------------------------------------------------------

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
```

### Step 3 - Create 2 instances(webserver instance, bastion instance) & RDS

```
-------------------------------------------------------------------
Creating webserver instance
-------------------------------------------------------------------

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

-------------------------------------------------------------------
Creating bastion instance
-------------------------------------------------------------------

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
```
> <b>Create AWS RDS</b>

It includes the creation of an RDS subnet group and an RDS instance.

aws_db_subnet_group resource: It creates an RDS subnet group with the name "rds_subnet".
The subnet_ids attribute specifies the IDs of the subnets where the RDS instance will be deployed. It references the IDs of two subnets using the aws_subnet.privatesubnets[0].id and aws_subnet.privatesubnets[1].id variables.

This configuration will provision an RDS instance with the specified settings and associate it with the specified subnets and security group(s).

```
-------------------------------------------------------------------
Create RDS
-------------------------------------------------------------------

resource "aws_db_subnet_group" "subnet_rds" {
  name       = "rds_subnet"
subnet_ids = [
    aws_subnet.privatesubnets[0].id,
    aws_subnet.privatesubnets[1].id
  ] 
}

resource "aws_db_instance" "rds" {
  engine               = "mariadb"
  instance_class       = "db.t2.micro"
  allocated_storage    = 10
  storage_type         = "gp2"
  identifier           = "wordpress-db"
  username             = "wp_user"
  password             = "********"
  db_subnet_group_name = aws_db_subnet_group.subnet_rds.name
  vpc_security_group_ids = [aws_security_group.backend.id]
}
```
### Step 4 - Configuring Route53

In this step, we create a private Route 53 zone with the name "ashna.local". The zone is associated with the VPC specified by aws_vpc.main.id. This allows us to manage DNS records privately within the VPC.
We pointed all instance's private IP to it's hostname. Also, we have added CNAME record in the private Route 53 zone for the subdomain "backend.ashna.local". It points the CNAME record to the RDS address specified as "wordpress-db.cyhsysz4vqez.ap-south-1.rds.amazonaws.com". Requests to "backend.ashna.local" will be redirected to the specified RDS address.

```
-------------------------------------------------------------------
Pointing blog.ashna.online to eip
-------------------------------------------------------------------

resource "aws_route53_record" "blog" {
  zone_id = data.aws_route53_zone.myzone.id
  name    = "blog"
  type    = "A"
  ttl     = 300
  records = [aws_eip.frontend.public_ip]
}

-------------------------------------------------------------------
Creating a private zone ashna.local
-------------------------------------------------------------------

resource "aws_route53_zone" "private" {
  name = "ashna.local"

  vpc {
    vpc_id = aws_vpc.main.id
  }
}

-------------------------------------------------------------------
Pointing bastion.ashna.local to bastion's private ip
-------------------------------------------------------------------

resource "aws_route53_record" "bastion" {
  zone_id = aws_route53_zone.private.zone_id
  name    = "bastion"
  type    = "A"
  ttl     = 300
  records = [aws_instance.bastion.private_ip]
}


-------------------------------------------------------------------
Pointing backend.ashna.local to RDS address
-------------------------------------------------------------------

resource "aws_route53_record" "backend" {
  zone_id = aws_route53_zone.private.zone_id
  name    = "backend"
  type    = "CNAME"
  ttl     = 300
  records = [aws_db_instance.rds.address]
}


-------------------------------------------------------------------
Pointing frontend.ashna.local to frontend's private ip
-------------------------------------------------------------------

resource "aws_route53_record" "frontend" {
  zone_id = aws_route53_zone.private.zone_id
  name    = "frontend"
  type    = "A"
  ttl     = 300
  records = [aws_instance.frontend.private_ip]
}

```
