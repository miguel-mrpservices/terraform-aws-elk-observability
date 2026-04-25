terraform {
  backend "s3" {
    bucket = "mrpservices-tfstates-dev"
    key    = "aws-elk-observability/terraform.tfstate"
    region = "eu-central-1"
  }
}