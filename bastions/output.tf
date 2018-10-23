output "instance_id" {
  description = "Bastion instance id"
  value       = "${module.bastion.instance_id}"
}

# Subnets
output "public_ip" {
  description = "Bastion public ip"
  value       = ["${module.bastion.public_ip}"]
}

output "ssh_user" {
  description = "SSH default user"
  value       = ["${module.bastion.ssh_user}"]
}