locals {
  instance_names = ["ubuntu1", "ubuntu2"]
  public_key     = file(pathexpand(var.ssh_public_key_path))
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

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
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

  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t2.micro"
  key_name                    = aws_key_pair.ubuntu.key_name
  subnet_id                   = data.aws_subnets.default_vpc.ids[count.index % length(data.aws_subnets.default_vpc.ids)]
  vpc_security_group_ids      = [aws_security_group.ssh.id]
  associate_public_ip_address = true

  tags = {
    Name = local.instance_names[count.index]
  }
}

resource "local_file" "ssh_config" {
  filename        = pathexpand(var.ssh_config_fragment_path)
  file_permission = "0600"
  content = join("\n", [
    for i, name in local.instance_names : <<-EOT
      Host ${name}
          HostName ${aws_instance.ubuntu[i].public_ip}
          User ubuntu
          IdentityFile ~/.ssh/id_ed25519
          IdentitiesOnly yes
    EOT
  ])
}
