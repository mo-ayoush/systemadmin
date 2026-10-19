locals {
  instance_names = ["ec2-1", "ec2-2"]
  vm_targets = {
    ubuntu1 = "192.168.8.102"
    ubuntu2 = "192.168.8.103"
  }
  public_key = file(pathexpand(var.ssh_public_key_path))
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default_vpc" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_ssm_parameter" "ubuntu_ami" {
  name = "/aws/service/canonical/ubuntu/server/noble/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

resource "aws_key_pair" "ubuntu" {
  key_name   = "systemadmin-ubuntu-key"
  public_key = local.public_key
}

resource "aws_security_group" "ssh" {
  name        = "systemadmin-ubuntu-ssh"
  description = "Allow SSH to the Ubuntu EC2 instances"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_ingress_cidr]
  }

  ingress {
    description = "Node Exporter metrics"
    from_port   = 9100
    to_port     = 9100
    protocol    = "tcp"
    cidr_blocks = [var.ssh_ingress_cidr]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "systemadmin-ubuntu-ssh"
  }
}

resource "aws_instance" "ubuntu" {
  count = length(local.instance_names)

  ami                         = data.aws_ssm_parameter.ubuntu_ami.value
  instance_type               = "t3.micro"
  key_name                    = aws_key_pair.ubuntu.key_name
  subnet_id                   = data.aws_subnets.default_vpc.ids[count.index % length(data.aws_subnets.default_vpc.ids)]
  vpc_security_group_ids      = [aws_security_group.ssh.id]
  associate_public_ip_address = true

  user_data = <<-USER_DATA
    #!/bin/bash
    set -euxo pipefail
    apt-get update
    apt-get install -y docker.io
    systemctl enable --now docker
    docker run -d \
      --name node-exporter \
      --restart unless-stopped \
      --network host \
      --pid host \
      -v "/:/host:ro,rslave" \
      prom/node-exporter:latest \
      --path.rootfs=/host
  USER_DATA

  tags = {
    Name = local.instance_names[count.index]
  }
}

resource "local_file" "prometheus_config" {
  filename        = "${path.module}/monitoring/prometheus.yml"
  file_permission = "0644"
  content = yamlencode({
    global = {
      scrape_interval = "15s"
    }
    scrape_configs = [{
      job_name = "servers"
      static_configs = concat(
        [
          for name, ip in local.vm_targets : {
            targets = ["${ip}:9100"]
            labels  = { server = "vm-${name}" }
          }
        ],
        [
          for i, name in local.instance_names : {
            targets = ["${aws_instance.ubuntu[i].public_ip}:9100"]
            labels  = { server = name }
          }
        ]
      )
    }]
  })
}

data "local_file" "existing_ssh_config" {
  filename = pathexpand(var.ssh_config_path)
}

locals {
  ssh_config_without_old_include = replace(
    data.local_file.existing_ssh_config.content,
    "/(?im)^Include[ \\t]+.*terraform-ubuntu-ec2\\.conf[ \\t]*\\r?\\n?/",
    ""
  )
  ssh_config_without_managed_block = replace(
    local.ssh_config_without_old_include,
    "/(?ms)^# BEGIN TERRAFORM MANAGED EC2 HOSTS\\r?\\n.*?^# END TERRAFORM MANAGED EC2 HOSTS\\r?\\n?/",
    ""
  )
}

resource "local_file" "ssh_config" {
  filename        = pathexpand(var.ssh_config_path)
  file_permission = "0600"
  content = <<-EOT
    ${trimspace(local.ssh_config_without_managed_block)}

    # BEGIN TERRAFORM MANAGED EC2 HOSTS
    ${join("\n", [
  for i, name in local.instance_names : <<-HOST
      Host ${name}
          HostName ${aws_instance.ubuntu[i].public_ip}
          User ubuntu
          IdentityFile ~/.ssh/id_ed25519
          IdentitiesOnly yes
      HOST
])}
    # END TERRAFORM MANAGED EC2 HOSTS
  EOT
}
