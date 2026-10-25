# Hybrid Infrastructure Monitoring

A small system administration portfolio project for monitoring a hybrid environment: two local Ubuntu virtual machines and two Ubuntu Amazon EC2 instances. It combines Prometheus metrics and Grafana dashboards with a separate SSH-based report script, plus Terraform-managed AWS resources and private S3 storage for audit reports.


## Goals

- View basic host metrics from local and cloud Ubuntu servers in one Prometheus/Grafana setup.
- Run an SSH script on the management machine to collect connection status, uptime, root filesystem usage, and readable SSH authentication-log counts.
- Provision the EC2 instances and report-storage bucket as Terraform configuration.
- Store report objects in a private S3 bucket with encryption and transport protections.

## Architecture

```text
Management laptop / Ubuntu host
├── VirtualBox: ubuntu1 and ubuntu2
├── Docker Compose: Prometheus and Grafana
└── ssh_server_report.sh ── SSH (TCP 22) ──> ubuntu1, ubuntu2, ec2-1, ec2-2

Prometheus ── scrapes Node Exporter (TCP 9100) ──> the four servers
Grafana ── queries Prometheus ──> dashboards
Terraform ── manages ──> AWS EC2, security group, SSH config, and S3 bucket
Audit report ── manual AWS CLI upload over HTTPS ──> private S3 bucket
```

Prometheus and the SSH report script serve different purposes. Prometheus repeatedly scrapes metrics; the script performs a check when run and prints a text report. The script does not itself upload reports to S3.

## Technologies

- Ubuntu Linux and VirtualBox for local virtual machines
- AWS EC2 and Amazon S3
- Terraform with the AWS and Local providers
- Docker Compose, Prometheus, Node Exporter, and Grafana
- OpenSSH and Bash
- AWS CLI for manual report uploads and verification

## Repository layout

| Path | Purpose |
|---|---|
| `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf` | EC2, SSH configuration, provider requirements, variables, and outputs |
| `audit_reports.tf` | Private S3 bucket, public-access block, ownership controls, default encryption, and TLS-only bucket policy |
| `ssh_server_report.sh` | On-demand SSH health and authentication-log report |
| `monitoring/prometheus.yml` | Static Prometheus scrape configuration; Terraform also defines a generated configuration for this path |
| `monitoring/docker-compose.yml` | Prometheus and Grafana container definitions and persistent volumes |
| `terraform-README.md` | Detailed Terraform, state-safety, and S3 upload instructions |
| `audit_log/` | Local report examples; ignored by Git |
| `results/` | Captured validation evidence; ignored by Git |
| `presentation/` | Project presentation |

## Prerequisites

- Terraform 1.5 or later
- AWS CLI and AWS credentials with permissions for the intended AWS resources
- Docker Engine with the Docker Compose plugin, for the monitoring containers
- Bash, OpenSSH client, `awk`, `sed`, `grep`, `df`, and `uptime`
- A local SSH key pair; the Terraform default public-key path is `~/.ssh/id_ed25519.pub`
- Two configured local Ubuntu VM targets and network connectivity from the management host

AWS charges may apply to cloud resources and data transfer. Check current AWS pricing and your account limits before provisioning anything.

## SSH server report

The script reads concrete `Host` aliases from `~/.ssh/config` by default. Each alias must have working non-interactive SSH authentication. It skips wildcard and negated host patterns, then connects to each alias and collects:

- SSH connection status
- Uptime
- Root filesystem usage (`/`)
- Counts of matching successful and failed SSH authentication log entries, when readable

The log totals are matching log lines, not necessarily unique sessions or a complete security audit. The script tries `journalctl` first, then readable `/var/log/auth.log` or `/var/log/secure` files. Remote permissions and log retention affect the result.

Examples:

```sh
# Show compact report using ~/.ssh/config
bash ssh_server_report.sh

# Use another SSH config and include detailed remote output
bash ssh_server_report.sh -f ./ssh_config -v

# Display the report and save a copy
bash ssh_server_report.sh -o ./ssh-report.txt

# Show supported options
bash ssh_server_report.sh -h
```

The script does not create a report file unless `-o` is supplied. It has no scheduler or S3 upload step built in.

## Terraform infrastructure

The Terraform configuration is set for `eu-central-1` (Frankfurt), uses the default VPC, and defines two Ubuntu EC2 `t3.micro` instances with public IPv4 addresses. EC2 user data installs Docker and runs Node Exporter. Terraform also generates Prometheus target configuration and manages EC2 host aliases in the configured OpenSSH config file.


The Terraform security-group variable `ssh_ingress_cidr` defaults to `0.0.0.0/0` and is used for both TCP 22 and TCP 9100. Restrict it to the necessary source address/range before provisioning. Port 9100 exposes metrics and should not be open to the public internet. Terraform also reads and writes the configured local SSH config path; review its planned local-file changes carefully.

The Terraform configuration refers to local VM targets `192.168.8.102` and `192.168.8.103`. Update these values for a different VM network before using that configuration. It also reads the public key at `~/.ssh/id_ed25519.pub` by default. Never put a private SSH key in this repository.

## Prometheus and Grafana

`monitoring/docker-compose.yml` defines Prometheus on TCP 9090 and Grafana on TCP 3000, with named volumes for their data. Prometheus uses `monitoring/prometheus.yml`, which configures a 15-second scrape interval and four Node Exporter targets on TCP 9100. The target addresses in the checked-in YAML are environment-specific; verify and update them for your environment. Terraform also generates this file from the configured VM addresses and EC2 public IPs during Terraform operations that apply the local-file resource.

Node Exporter provides host metrics. Prometheus scrapes and stores them; Grafana queries Prometheus and presents dashboards. 

Example local startup and shutdown commands:

```sh
docker compose -f monitoring/docker-compose.yml up -d
docker compose -f monitoring/docker-compose.yml ps
docker compose -f monitoring/docker-compose.yml down
```

These commands manage local containers only. They do not provision the EC2 instances or create the required Node Exporter services on the two local VMs. Confirm that all four endpoints are reachable from Prometheus before relying on dashboard data.

## Private S3 report storage

`audit_reports.tf` defines a dedicated S3 bucket with all four Block Public Access controls enabled, Bucket Owner Enforced ownership, default SSE-KMS encryption using the AWS-managed `alias/aws/s3` key, and a bucket policy that denies requests without secure transport (TLS). Terraform does not create a customer-managed KMS key.

Report upload is a separate, manual AWS CLI operation. The script does not upload reports, and the repository does not configure a recurring upload schedule. Follow the state, bucket-name, upload, and verification guidance in [`terraform-README.md`](terraform-README.md). It includes conditional upload and checksum verification examples. Use a globally unique bucket name and confirm the intended AWS identity and region before performing an upload.

## Security considerations

- Restrict SSH (TCP 22) to trusted source addresses and metrics (TCP 9100) to the Prometheus host. Review the Terraform default before use.
- Replace the example Grafana password; supply secrets outside version control.
- Keep private SSH keys and AWS credentials out of the repository. The `.gitignore` excludes several local state, credential, and report paths, but always inspect `git status` before publishing.
- S3 public-access blocking does not replace IAM controls. Grant only the permissions needed to upload and read reports.
- The SSH report counts selected log patterns. It is a troubleshooting/audit aid, not intrusion detection or proof that no unauthorized access occurred.
- Prometheus and Grafana configuration or screenshots do not prove that services and targets are currently healthy. Check their live status before making operational claims.
- Terraform state can contain sensitive infrastructure details. Protect state and backups and do not publish them.

## Troubleshooting and limitations

- **SSH connection fails:** check the alias, hostname/IP, username, key path, network route, security-group rules, and non-interactive key authentication. The script uses an 8-second connection timeout.
- **Authentication counts are unavailable:** the remote account may not have permission to read the journal or authentication logs, or logs may not be present/retained.
- **Prometheus target is down:** confirm Node Exporter is running and reachable on TCP 9100, the target address is correct, and the network/security-group rules permit scraping.
- **Grafana has no data:** verify Prometheus is reachable, a Prometheus data source is configured in Grafana, and the queried metric exists. The Compose file defines the services but does not provision a dashboard or data source automatically.
- **Terraform proposes unexpected changes:** stop and inspect state, configuration, and the complete plan. The documented state/backup mismatch must be resolved first.
- **Bucket creation fails:** S3 bucket names are globally unique. Choose an available name and set `audit_reports_bucket_name` appropriately after reviewing the Terraform state.
- The Prometheus target list contains fixed VM addresses and generated EC2 addresses; it needs maintenance when addresses or topology change.
- A scrape interval of 15 seconds and a successful scrape do not guarantee application-level health.

## Safe cleanup

Do not run `terraform destroy` as a general cleanup step. First reconcile the Terraform state with the real AWS resources, inspect a reviewed plan, and identify exactly which resources and data would be removed. EC2 instances, S3 bucket configuration, and stored S3 objects have different lifecycles; removing the Terraform stack is not a substitute for reviewing retained report data. For local containers, `docker compose ... down` stops and removes the containers but leaves named volumes unless explicitly removed. Preserve report data and Terraform state backups until they are no longer needed.

## License

No license file is present in this repository. Contact the repository owner before reusing or redistributing the project.
