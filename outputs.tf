output "instance_public_ips" {
  description = "Public IPv4 addresses for ubuntu1 and ubuntu2."
  value = {
    for i, name in local.instance_names : name => aws_instance.ubuntu[i].public_ip
  }
}

output "ssh_config_fragment" {
  description = "Path to the generated SSH config fragment. Include it at the top of ~/.ssh/config."
  value       = local_file.ssh_config.filename
}
