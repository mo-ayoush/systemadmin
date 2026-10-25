variable "aws_region" {
  description = "AWS region; eu-central-1 is Frankfurt."
  type        = string
  default     = "eu-central-1"
}

variable "audit_reports_bucket_name" {
  description = "Globally unique name for the private S3 bucket that stores audit reports."
  type        = string
  nullable    = false
  default     = "audit-log-reports-eu-central-1-20261020-a84d91c7f263"

  validation {
    condition = (
      can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.audit_reports_bucket_name)) &&
      !can(regex("\\.\\.", var.audit_reports_bucket_name)) &&
      !can(regex("^[0-9]{1,3}(\\.[0-9]{1,3}){3}$", var.audit_reports_bucket_name)) &&
      !startswith(var.audit_reports_bucket_name, "xn--") &&
      !startswith(var.audit_reports_bucket_name, "sthree-") &&
      !startswith(var.audit_reports_bucket_name, "amzn-s3-demo-") &&
      !endswith(var.audit_reports_bucket_name, "-s3alias") &&
      !endswith(var.audit_reports_bucket_name, "--ol-s3") &&
      !endswith(var.audit_reports_bucket_name, ".mrap") &&
      !endswith(var.audit_reports_bucket_name, "--x-s3") &&
      !endswith(var.audit_reports_bucket_name, "--table-s3") &&
      !endswith(var.audit_reports_bucket_name, "-an")
    )
    error_message = "The bucket name must follow Amazon S3 general purpose bucket naming rules."
  }
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

variable "ssh_config_path" {
  description = "Path to the OpenSSH client config Terraform updates with the EC2 aliases."
  type        = string
  default     = "~/.ssh/config"
}
