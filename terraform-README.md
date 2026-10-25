# Ubuntu EC2 instances and audit report storage

This Terraform configuration creates two Ubuntu 24.04 LTS `t3.micro` instances
in the AWS Frankfurt region (`eu-central-1`), in the default VPC. Each gets a
public IPv4 address. It imports the public key from `~/.ssh/id_ed25519.pub`;
the private key stays on your machine.

## Important: check Terraform state before running Terraform

**The current `terraform.tfstate` is empty while `terraform.tfstate.backup`
records existing EC2 infrastructure. Do not run `terraform apply` or
`terraform destroy` until you have verified the actual AWS resources, resolved
which state is authoritative, and reviewed a Terraform plan that does not
recreate or destroy the existing EC2 resources. Do not copy or restore the
backup over the current state without first resolving that mismatch.**

## Existing EC2 infrastructure

Make sure the AWS CLI credentials/profile are configured and
`~/.ssh/id_ed25519.pub` exists. Then run:

```sh
terraform init
```

After the state mismatch is resolved, review a Terraform plan before applying
any changes. The configured bucket-name default is
`audit-log-reports-eu-central-1-20261020-a84d91c7f263`; its global availability
has not been checked. Change it with `-var='audit_reports_bucket_name=NAME'`
only after choosing and checking the intended name.

Terraform writes the dynamic `ubuntu1` and `ubuntu2` host entries to
`~/.ssh/terraform-ubuntu-ec2.conf`. Add this line at the very top of
`~/.ssh/config`, before any existing `Host ubuntu1` or `Host ubuntu2` entries:

```sshconfig
Include ~/.ssh/terraform-ubuntu-ec2.conf
```

The default security group rule opens TCP port 22 from anywhere so the
instances are reachable from changing client IPs. The following is an optional
SSH security-group change; it is unrelated to S3. Do not run it until the state
mismatch above has been resolved and a safe plan reviewed. For better security,
set `ssh_ingress_cidr` to your current public address in `/32` notation, for
example:

```sh
terraform apply -var='ssh_ingress_cidr=203.0.113.10/32'
```

Connect with `ssh ubuntu1` or `ssh ubuntu2`. `terraform destroy` removes the
entire Terraform-managed stack, including both EC2 instances; do not use it for
S3-only cleanup. Review a separate cleanup plan after the demonstration before
removing any audit-report resources or objects.

## Private S3 storage for audit reports

The configuration defines a dedicated private S3 bucket for files in
`audit_log`, using the default name above. Confirm that the name is available
before applying, and resolve the state mismatch first.

The bucket uses all four S3 Block Public Access settings, Bucket Owner Enforced
ownership, default SSE-KMS with the AWS-managed `aws/s3` key, and a bucket policy
that denies non-TLS requests. Terraform does not create a KMS key.

After the bucket exists and AWS identity, region, and state have been checked,
set `BUCKET` to its name. This loop uploads regular files directly inside
`audit_log` without recursing into subdirectories. It sends original files as
they are and asks S3 to reject any key that already exists. A conflict stops
that upload; it does not overwrite the object.

```sh
BUCKET='your-globally-unique-name'
for file in audit_log/*; do
  [ -f "$file" ] || continue
  aws s3api put-object \
    --region eu-central-1 \
    --bucket "$BUCKET" \
    --key "$(basename "$file")" \
    --body "$file" \
    --server-side-encryption aws:kms \
    --ssekms-key-id alias/aws/s3 \
    --if-none-match '*' \
    --checksum-algorithm SHA256
done
```

The command does not modify or delete local files. S3 validates the supplied
SHA-256 checksum during each upload. If a key already exists, the conditional
write fails; inspect it rather than retrying with a normal copy command.

To check the uploaded object and its encryption, run this for each report,
replacing the filename:

```sh
aws s3api head-object \
  --region eu-central-1 \
  --bucket "$BUCKET" \
  --key 'report-name.log' \
  --query '{SSE:ServerSideEncryption,KMSKey:SSEKMSKeyId,ChecksumSHA256:ChecksumSHA256}' \
  --checksum-mode ENABLED
```

`SSE` should be `aws:kms`. To independently compare downloaded bytes, compare
`sha256sum audit_log/report-name.log` with
`aws s3 cp "s3://$BUCKET/report-name.log" - | sha256sum`.
The bucket policy rejects HTTP requests; use HTTPS, which is the AWS CLI default.
The CLI uses the currently configured AWS credentials and stores none in this
project.
