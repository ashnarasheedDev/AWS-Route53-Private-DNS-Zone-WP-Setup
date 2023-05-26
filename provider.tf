provider "aws" {
  region     = "ap-south-1"
  access_key = "****************"
  secret_key = "*****************************"

  default_tags {
    tags = {
      "Project" = var.project_name
      "Env"     = var.project_environment
    }
  }
}
