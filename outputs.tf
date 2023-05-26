output "az1" {
  value = data.aws_availability_zones.azs.names[0]

}




output "az2" {
  value = data.aws_availability_zones.azs.names[1]

}

output "az3" {
  value = data.aws_availability_zones.azs.names[2]

}




output "subnet1" {
  value = cidrsubnet(var.vpc_cidr, 3, 0)
}

output "subnet2" {
  value = cidrsubnet(var.vpc_cidr, 3, 1)
}

output "subnet3" {
  value = cidrsubnet(var.vpc_cidr, 3, 2)
}

output "subnet4" {
  value = cidrsubnet(var.vpc_cidr, 3, 3)
}

output "subnet5" {
  value = cidrsubnet(var.vpc_cidr, 3, 4)
}

output "subnet6" {
  value = cidrsubnet(var.vpc_cidr, 3, 5)
}
output "frontend-public-ip" {
  value = aws_eip.frontend.public_ip
}

output "frontend-private-ip" {
  value = aws_instance.frontend.private_ip
}

output "bastion-public-ip" {
  value = aws_instance.bastion.public_ip
}

output "bastion-private-ip" {
  value = aws_instance.bastion.private_ip
}

output "webserver_url" {
  value = "https://${var.frontend_hostname}.${var.domain_name}"
}
