variable "ami_id" {

  description = "ami id of amazon linux"
  type        = string
  default     = "ami-0c768662cc797cd75"

}

variable "instance_type" {
  description = "ec2 instance type"
  type        = string
  default     = "t2.micro"

}

variable "project_name" {
  description = "your project name"
  type        = string
  default     = "zomato"
}

variable "project_environment" {
  description = "project environment"
  type        = string
  default     = "dev"
}

variable "aws_region" {

  default = "ap-south-1"
}

variable "vpc_cidr" {
  default = "10.1.0.0/16"
  type    = string
}
variable "domain_name" {
  default = "ashna.online"
}

variable "frontend_hostname" {
  default = "blog"
}
