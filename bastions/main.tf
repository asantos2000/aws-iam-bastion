provider "aws" {
  region = "us-west-2"
}

module "bastion" {
  source = ".."

  name = "bastion"
  namespace = "mt"
  stage = "bastion-test"
  vpc_id = "vpc-asasasasas"
  ami = "ami-efd0428f"
  subnets = ["subnet-asasasasas"]
  key_name = "bastion-test"
  ssh_user = "ubuntu"
  security_groups = ["sg-asasasasas"]
  create_eip = false
  eip_id = "eipalloc-asasasasas"

  user_data_str = "${file("./user_data.sh")}"

  tags = {
    Owner       = "my-team"
    Environment = "dev"
    Name        = "Bastion"
  }
}