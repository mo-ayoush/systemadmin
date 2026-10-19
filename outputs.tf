output "instance_public_ips" {
  description = "Public IPv4 addresses for ec2-1 and ec2-2."
  value = {
    for i, name in local.instance_names : name => aws_instance.ubuntu[i].public_ip
  }
}

output "ssh_config_path" {
  description = "Path to the OpenSSH config updated with the EC2 aliases."
  value       = local_file.ssh_config.filename
}
