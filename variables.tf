variable "aws_region" {
  description = "AWS region; eu-central-1 is Frankfurt."
  type        = string
  default     = "eu-central-1"
}

variable "ssh_public_key_path" {
  description = "Path to the public half of the SSH key used by ubuntu1 and ubuntu2."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "ssh_ingress_cidr" {
  description = "IPv4 CIDR allowed to connect to SSH (port 22). Set this to your public IP/32 for tighter access."
  type        = string
  default     = "0.0.0.0/0"
}

variable "ssh_config_fragment_path" {
  description = "Path where Terraform writes SSH host aliases after creating the instances."
  type        = string
  default     = "~/.ssh/terraform-ubuntu-ec2.conf"
}
