# Ubuntu EC2 instances

This Terraform configuration creates two Ubuntu 24.04 LTS `t2.micro` instances
in the AWS Frankfurt region (`eu-central-1`), in the default VPC. Each gets a
public IPv4 address. It imports the public key from `~/.ssh/id_ed25519.pub`;
the private key stays on your machine.

## Run

Make sure the AWS CLI credentials/profile are configured and
`~/.ssh/id_ed25519.pub` exists. Then run:

```sh
terraform init
terraform plan
terraform apply
```

Terraform writes the dynamic `ubuntu1` and `ubuntu2` host entries to
`~/.ssh/terraform-ubuntu-ec2.conf`. Add this line at the very top of
`~/.ssh/config`, before any existing `Host ubuntu1` or `Host ubuntu2` entries:

```sshconfig
Include ~/.ssh/terraform-ubuntu-ec2.conf
```

The default security group rule opens TCP port 22 from anywhere so the
instances are reachable from changing client IPs. For better security, set
`ssh_ingress_cidr` to your current public address in `/32` notation, for example:

```sh
terraform apply -var='ssh_ingress_cidr=203.0.113.10/32'
```

Connect with `ssh ubuntu1` or `ssh ubuntu2`. Destroy the resources with
`terraform destroy`; this also removes the generated SSH fragment.
