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

