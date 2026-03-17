# Online Boutique – AWS EKS + GitLab CI/CD

A cloud-native microservices e-commerce application, refactored from Google's GKE/GCP demo to run on **AWS EKS** with a **GitLab CI/CD** pipeline for automated infrastructure provisioning and application deployment.

> **Upstream source:** [GoogleCloudPlatform/microservices-demo](https://github.com/GoogleCloudPlatform/microservices-demo)

---

## Table of contents

1. [Architecture overview](#architecture-overview)
2. [Production design decisions](#production-design-decisions)
3. [Repository layout](#repository-layout)
4. [Prerequisites](#prerequisites)
5. [Part 1 – AWS bootstrap](#part-1--aws-bootstrap)
6. [Part 2 – Local deployment](#part-2--local-deployment)
7. [Part 3 – GitLab CI/CD pipeline](#part-3--gitlab-cicd-pipeline)
8. [Deployment variations](#deployment-variations)
9. [Useful commands](#useful-commands)
10. [Teardown](#teardown)
11. [Troubleshooting](#troubleshooting)

---

## Architecture overview

```
GitLab CI/CD Pipeline
        │
        ├─ validate  →  terraform fmt / validate, yamllint
        ├─ plan      →  terraform plan (every push)
        ├─ apply     →  terraform apply (main branch, manual gate)
        ├─ deploy    →  kubectl apply via kustomize
        ├─ verify    →  smoke-test ELB endpoint
        └─ destroy   →  terraform destroy (manual)

AWS Infrastructure (Terraform – modular)
        │
        ├─ modules/vpc          → VPC, subnets, NAT gateways
        ├─ modules/eks          → EKS cluster, node group, IRSA, Pod Security Standards
        ├─ modules/elasticache  → Managed Redis (HA in prod, single node in dev)
        └─ modules/gitlab-oidc  → OIDC provider + scoped IAM role (no long-lived keys)

Kubernetes (11 microservices + production add-ons)
        frontend ── checkoutservice ── paymentservice
                 ├─ productcatalogservice
                 ├─ currencyservice
                 ├─ cartservice ── redis-cart (or ElastiCache)
                 ├─ shippingservice
                 ├─ recommendationservice
                 ├─ emailservice
                 ├─ adservice
                 └─ loadgenerator (synthetic traffic, removed in staging/prod)
```

---

## Production design decisions

This section explains the specific choices made to bring the project to a production-grade standard.

### 1. No long-lived AWS credentials — GitLab OIDC federation

**Problem:** Storing `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` as GitLab CI variables creates static, long-lived secrets that never expire. If a GitLab variable is leaked (via logs, a compromised runner, or an accidental echo), the key remains valid indefinitely.

**Solution:** GitLab OIDC federation via `aws sts assume-role-with-web-identity`.

How it works:
1. GitLab's identity service issues a signed JSON Web Token (JWT) to each CI job when `id_tokens` is defined in the job configuration.
2. The job calls `aws sts assume-role-with-web-identity`, passing that JWT.
3. AWS validates the JWT's signature against the registered OIDC provider (`gitlab.com`) and checks the `sub` claim — which encodes the project path and branch — against the IAM role's trust policy.
4. AWS returns temporary credentials (Access Key ID, Secret Access Key, Session Token) that **expire automatically** when the job ends (max 1 hour).

The only CI variable needed is `CI_AWS_ROLE_ARN` — the ARN of the IAM role. It is not a secret.

The IAM role is created and managed by the **`terraform/modules/gitlab-oidc/`** module. Its trust policy is scoped to a single GitLab project path and branch pattern (e.g., `main`-only for prod), so a token from any other project or branch is rejected by AWS.

```
                          ┌─────────────────────────────────┐
GitLab Job                │  AWS STS                        │
  id_tokens:              │                                 │
    GITLAB_OIDC_TOKEN ──► │  assume-role-with-web-identity  │
                          │  validates JWT against OIDC     │
                          │  provider (gitlab.com)          │
                          │                                 │
                          │  ◄── temp credentials (1hr)     │
                          └─────────────────────────────────┘
```

**What you remove from GitLab CI/CD Variables:** `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`.
**What you add:** `CI_AWS_ROLE_ARN` (the IAM role ARN — not a secret).

---

### 2. Modular Terraform

**Problem:** A flat `terraform/` directory with all resources in a few files does not scale. It is difficult to reuse logic across environments, test modules independently, or reason about the blast radius of a change.

**Solution:** The infrastructure is split into four focused, reusable modules:

| Module | Responsibility |
|---|---|
| `modules/vpc` | VPC, public/private subnets, NAT gateways, route tables, EKS subnet tags |
| `modules/eks` | EKS cluster, managed node group, IRSA, EBS CSI add-on, application namespace |
| `modules/elasticache` | ElastiCache Redis replication group, subnet group, security group |
| `modules/gitlab-oidc` | IAM OIDC provider, CI role, least-privilege deploy policy |

Each module has a clean `variables.tf` / `main.tf` / `outputs.tf` contract. Modules are called by environment-specific root configurations in `terraform/environments/`:

```
terraform/
├── modules/
│   ├── vpc/
│   ├── eks/
│   ├── elasticache/
│   └── gitlab-oidc/
└── environments/
    ├── dev/    ← public API endpoint, t3.medium, 1 NAT gateway
    └── prod/   ← downsized POC defaults with production values commented inline
```

Each environment has its own Terraform state key (`online-boutique/dev/terraform.tfstate` vs `online-boutique/prod/terraform.tfstate`), preventing a plan in one environment from touching another.

Current resource sizing (this is a personal portfolio POC — production-grade values are commented out in each `terraform.tfvars` file):

| Setting | dev | prod (POC) | prod recommendation |
|---|---|---|---|
| EKS API endpoint | public | public | private (VPC/VPN only) |
| Instance type | `t3.medium` | `t3.medium` | `m5.large` |
| Min / desired / max nodes | 1 / 2 / 4 | 1 / 2 / 4 | 3 / 3 / 10 |
| Node disk | 50 GiB | 50 GiB | 100 GiB |
| NAT gateways | 1 shared | 1 shared | 1 per AZ (HA) |
| ElastiCache replicas | 1, no Multi-AZ | 1, no Multi-AZ | 2, Multi-AZ failover |
| ElastiCache node type | `cache.t3.micro` | `cache.t3.micro` | `cache.r6g.large` |
| Snapshot retention | 1 day | 1 day | 7 days |

To switch a setting to the production-grade value, uncomment the relevant line in `terraform/environments/prod/terraform.tfvars`.

---

### 3. Horizontal Pod Autoscaler (HPA)

**Problem:** A fixed replica count cannot handle traffic spikes and wastes capacity during low-traffic periods.

**Solution:** `kubernetes/hpa.yaml` defines HPAs for the five most CPU-sensitive services (frontend, checkoutservice, cartservice, productcatalogservice, recommendationservice). Each HPA:

- Keeps a minimum of **2 replicas** so the service survives a single pod failure.
- Scales up when average CPU utilisation exceeds **60%**.
- Caps at a maximum replica count to prevent runaway scaling.

Requires the Kubernetes Metrics Server, which is included in EKS managed clusters.

---

### 4. PodDisruptionBudgets (PDB)

**Problem:** Kubernetes node drains and rolling upgrades can temporarily take down all replicas of a service if nothing constrains how many pods can be evicted simultaneously.

**Solution:** `kubernetes/pdb.yaml` sets `minAvailable: 1` for every critical service (frontend, checkout, cart, payment, product catalog, currency, shipping). This tells the Kubernetes eviction API: *"you may not take the last pod — leave at least one running."*

Combined with the HPAs (which ensure at least 2 replicas), a PDB with `minAvailable: 1` means a node drain can proceed without any service going fully down.

---

### 5. NetworkPolicies — zero-trust pod networking

**Problem:** By default, all pods in a Kubernetes namespace can communicate freely with each other. If one service is compromised, an attacker can reach every other service on the internal network.

**Solution:** `kubernetes/network-policies.yaml` implements a zero-trust posture:

1. A `default-deny-all` policy blocks all ingress and egress for every pod.
2. A `allow-dns-egress` policy re-opens UDP/TCP port 53 for CoreDNS (every pod needs DNS).
3. Per-service policies then open only the exact ports and peer pods that each service legitimately needs.

For example, `paymentservice` accepts connections only from `checkoutservice` on port 50051 — nothing else can reach it, even from within the namespace. This limits lateral movement to a single hop if a service is compromised.

---

### 6. EKS hardening

| Hardening measure | Implementation | Why |
|---|---|---|
| IMDSv2 enforced | `metadata_options.http_tokens = required` in node group | Blocks SSRF attacks that try to steal node IAM credentials via the EC2 metadata endpoint (CVE class) |
| Pod Security Standards | `pod-security.kubernetes.io/enforce: baseline` on namespace (`audit` and `warn` set to `restricted`) | Blocks known privilege-escalation vectors (host namespaces, privileged containers) without requiring explicit seccompProfile on every pod — `restricted` is the upgrade target once workloads carry full security contexts |
| Private API endpoint enabled | `cluster_endpoint_private_access = true` | Workers always use the private endpoint; the public endpoint is disabled in prod |
| IRSA (IAM Roles for Service Accounts) | `enable_irsa = true` | Pods get scoped AWS credentials via a projected service account token, not node-level instance profile credentials |
| AL2023 AMI | `ami_type = AL2023_x86_64_STANDARD` | Latest LTS Amazon Linux, receives regular security patches |

---

## Repository layout

```
.
├── .gitlab-ci.yml                       # CI/CD pipeline (OIDC-based AWS auth)
│
├── terraform/
│   ├── modules/
│   │   ├── vpc/                         # VPC, subnets, NAT gateways
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   ├── eks/                         # EKS cluster, node group, IRSA
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   ├── elasticache/                 # Managed Redis (optional)
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   └── gitlab-oidc/                 # OIDC provider + CI IAM role
│   │       ├── main.tf
│   │       ├── variables.tf
│   │       └── outputs.tf
│   │
│   ├── environments/
│   │   ├── dev/                         # Dev environment root config
│   │   │   ├── main.tf
│   │   │   ├── providers.tf
│   │   │   ├── variables.tf
│   │   │   ├── outputs.tf
│   │   │   └── terraform.tfvars
│   │   └── prod/                        # Prod environment root config
│   │       ├── main.tf
│   │       ├── providers.tf
│   │       ├── variables.tf
│   │       ├── outputs.tf
│   │       └── terraform.tfvars
│   │
│   ├── main.tf                          # Single-env root (calls modules)
│   ├── providers.tf                     # AWS, Kubernetes, Helm providers
│   ├── variables.tf                     # All input variables
│   ├── outputs.tf                       # Cluster outputs
│   └── terraform.tfvars.example         # Template – copy and fill in
│
├── kubernetes/
│   ├── manifests.yaml                   # 11 microservice Deployments + Services
│   ├── hpa.yaml                         # Horizontal Pod Autoscalers
│   ├── pdb.yaml                         # PodDisruptionBudgets
│   └── network-policies.yaml            # Zero-trust NetworkPolicies
│
└── kustomize/
    ├── kustomization.yaml               # Base resources + optional overlays
    └── components/
        └── without-loadgenerator/       # Removes loadgenerator (staging/prod)
```

---

## Prerequisites

| Tool | Minimum version | Install |
|---|---|---|
| Terraform | 1.5.0 | [developer.hashicorp.com/terraform/install](https://developer.hashicorp.com/terraform/install) |
| AWS CLI | 2.x | [aws.amazon.com/cli](https://aws.amazon.com/cli/) |
| kubectl | 1.28 | [kubernetes.io/docs/tasks/tools](https://kubernetes.io/docs/tasks/tools/) |
| kustomize | 5.x | [kubectl.sigs.k8s.io](https://kubectl.sigs.k8s.io/installation/kustomize/) |
| Git | any | — |

---

## Part 1 – AWS bootstrap

These steps are performed **once** by a human with admin-level AWS access. After this, the pipeline needs no static credentials.

### 1.1 Create the Terraform state backend

```bash
# S3 bucket for remote state
aws s3api create-bucket \
  --bucket my-tf-state-online-boutique \
  --region us-east-1

aws s3api put-bucket-versioning \
  --bucket my-tf-state-online-boutique \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket my-tf-state-online-boutique \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

# DynamoDB table for state locking
aws dynamodb create-table \
  --table-name tf-state-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

### 1.2 Bootstrap the GitLab OIDC trust (one-off local apply)

This creates the IAM OIDC provider and the CI role that all future pipeline runs will use. You need temporary admin-level credentials for this step only.

```bash
# Configure your local AWS credentials (these are only used for this bootstrap)
aws configure

# Edit terraform/environments/dev/terraform.tfvars and fill in:
#   gitlab_project_path = "your-gitlab-group/online-boutique"
#   tf_state_bucket     = "my-tf-state-online-boutique"
#   tf_lock_table       = "tf-state-lock"

cd terraform/environments/dev

terraform init \
  -backend-config="bucket=my-tf-state-online-boutique" \
  -backend-config="region=us-east-1" \
  -backend-config="dynamodb_table=tf-state-lock"

# Bootstrap ONLY the OIDC module first — this is all the pipeline needs to self-authenticate.
# The pipeline provisions the rest of the infrastructure on its own after this step.
terraform apply -target=module.gitlab_oidc
```

After apply completes, copy the role ARN from the output:

```
Outputs:
  gitlab_ci_role_arn = "arn:aws:iam::123456789012:role/gitlab-ci-oidc-role"
```

You will set this as `CI_AWS_ROLE_ARN` in the next step. **This is the last time you will need local AWS credentials for this project.**

### 1.3 Set GitLab CI/CD variables

Go to your GitLab project → **Settings → CI/CD → Variables** and add:

| Variable | Value | Sensitive? |
|---|---|---|
| `CI_AWS_ROLE_ARN` | ARN from step 1.2 (e.g. `arn:aws:iam::123456789012:role/gitlab-ci-oidc-role`) | No — it's just an ARN |
| `AWS_DEFAULT_REGION` | `us-east-1` | No |
| `TF_STATE_BUCKET` | `my-tf-state-online-boutique` | No |
| `TF_LOCK_TABLE` | `tf-state-lock` | No |
| `TF_VAR_cluster_name` | `online-boutique` | No |
| `TF_VAR_environment` | `dev` | No |

> **Notice:** There is no `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY`. GitLab CI exchanges a short-lived OIDC token for temporary credentials on every job run. See [Production design decisions → No long-lived credentials](#1-no-long-lived-aws-credentials--gitlab-oidc-federation).

---

## Part 2 – Local deployment

Use this path to deploy directly from your workstation.

### 2.1 Clone and configure

```bash
git clone https://gitlab.com/<your-group>/online-boutique.git
cd online-boutique
```

Edit the dev tfvars with your values:

```bash
# terraform/environments/dev/terraform.tfvars is already present.
# Fill in the three placeholder values:
#   gitlab_project_path
#   tf_state_bucket
#   tf_lock_table
```

### 2.2 Initialise Terraform

```bash
cd terraform/environments/dev

terraform init \
  -backend-config="bucket=my-tf-state-online-boutique" \
  -backend-config="region=us-east-1" \
  -backend-config="dynamodb_table=tf-state-lock"
```

### 2.3 Review the plan

```bash
terraform plan
```

### 2.4 Apply – provision the EKS cluster

```bash
terraform apply
```

This step creates the VPC, subnets, NAT gateways, EKS cluster, node groups, and GitLab OIDC role. It takes roughly **10–15 minutes**.

When complete, note the outputs:

```
cluster_name       = "online-boutique-dev"
cluster_endpoint   = "https://XXXXXXXX.gr7.us-east-1.eks.amazonaws.com"
kubeconfig_command = "aws eks update-kubeconfig --region us-east-1 --name online-boutique-dev"
gitlab_ci_role_arn = "arn:aws:iam::123456789012:role/gitlab-ci-oidc-role"
```

### 2.5 Configure kubectl

```bash
aws eks update-kubeconfig --region us-east-1 --name online-boutique-dev

# Verify nodes are ready
kubectl get nodes
```

### 2.6 Deploy the application

```bash
# Create the namespace
kubectl create namespace online-boutique

# Deploy with kustomize (includes HPA, PDB, and NetworkPolicies)
# --load-restrictor=none is required because kustomize/kustomization.yaml
# references files in ../kubernetes/, which is outside the build root.
kustomize build --load-restrictor=LoadRestrictionsNone ./kustomize/ | kubectl apply -n online-boutique -f -

# Or deploy the base manifest only
kubectl apply -n online-boutique -f kubernetes/manifests.yaml
```

### 2.7 Access the frontend

```bash
kubectl get svc frontend-external -n online-boutique
```

Copy the `EXTERNAL-IP` (an AWS ELB hostname) and open `http://<EXTERNAL-IP>` in your browser.

> DNS propagation for a new ELB can take 1–2 minutes.

---

## Part 3 – GitLab CI/CD pipeline

### 3.1 Push the repository to GitLab

```bash
git remote add origin https://gitlab.com/<your-group>/<your-project>.git
git push -u origin main
```

### 3.2 Pipeline stages

Every push triggers the pipeline automatically.

```
validate ──► plan ──► apply* ──► deploy ──► verify
                                              │
                                         destroy*
```

`*` = manual trigger required.

| Stage | Job | Runs when | What it does |
|---|---|---|---|
| validate | `terraform:fmt` | Every push | Checks Terraform formatting |
| validate | `terraform:validate` | Every push | Validates Terraform config |
| validate | `yaml:lint` | Every push | Lints all Kubernetes YAML |
| plan | `terraform:plan` | Every push | Generates and saves a plan artifact |
| apply | `terraform:apply` | `main` branch, **manual** | Provisions the EKS cluster |
| deploy | `app:deploy` | After apply | Deploys all microservices via kustomize |
| verify | `app:smoke-test` | After deploy | Polls ELB hostname, hits `/_healthz` |
| destroy | `terraform:destroy` | Any branch, **manual** | Tears down all AWS infrastructure |

### 3.3 OIDC credential flow in the pipeline

Each AWS-facing job contains this block:

```yaml
id_tokens:
  GITLAB_OIDC_TOKEN:
    aud: "https://gitlab.com"
```

GitLab injects a signed JWT into `GITLAB_OIDC_TOKEN`. The `before_script` then exchanges it:

```bash
CREDS=$(aws sts assume-role-with-web-identity \
  --role-arn "${CI_AWS_ROLE_ARN}" \
  --role-session-name "gitlab-$(echo "${CI_JOB_NAME}" | tr ':' '-')-${CI_JOB_ID}" \
  --web-identity-token "${GITLAB_OIDC_TOKEN}" \
  --duration-seconds 3600 \
  --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
  --output text)
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_SESSION_TOKEN=...
```

The credentials are session-scoped, never stored anywhere, and expire when the job ends.

### 3.4 Trigger the first pipeline deployment

1. Open your project → **CI/CD → Pipelines**.
2. The `validate` and `plan` stages run automatically — review the plan in the job log.
3. Click **play** on `terraform:apply` to provision the EKS cluster.
4. Once apply completes, `app:deploy` and `app:smoke-test` run automatically.
5. Check the `app:smoke-test` log for the frontend URL:
   ```
   Frontend URL: http://<elb-hostname>
   Health check passed (HTTP 200)
   ```

---

## Deployment variations

### Option A – Remove the load generator (staging / prod)

Uncomment the component in [kustomize/kustomization.yaml](kustomize/kustomization.yaml):

```yaml
components:
  - components/without-loadgenerator
```

Commit and push. The `loadgenerator` Deployment is deleted on the next deploy.

### Option B – Use AWS ElastiCache instead of in-cluster Redis

1. Set `enable_elasticache = true` in your environment's `terraform.tfvars`.
2. Run `terraform apply` — ElastiCache is provisioned and the endpoint is written to a ConfigMap automatically.
3. Uncomment `- components/elasticache-redis` in `kustomize/kustomization.yaml` to patch `cartservice` to use the ConfigMap value.

The in-cluster `redis-cart` pod can then be removed by deleting it from `manifests.yaml`.

### Option C – Use an NLB instead of a Classic ELB

Annotate the `frontend-external` Service in [kubernetes/manifests.yaml](kubernetes/manifests.yaml):

```yaml
metadata:
  name: frontend-external
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
```

### Option D – Deploy to prod

1. Edit `terraform/environments/prod/terraform.tfvars` with your values.
2. Set the GitLab CI variable `TF_VAR_environment` to `prod` and `TF_VAR_cluster_name` to `online-boutique-prod`.
3. The pipeline uses a separate state key (`online-boutique/prod/terraform.tfstate`) and the OIDC role is restricted to `main`-branch tokens only.

---

## Useful commands

```bash
# Check HPA status
kubectl get hpa -n online-boutique

# Check PDB status
kubectl get pdb -n online-boutique

# Check NetworkPolicy rules
kubectl get networkpolicies -n online-boutique

# View all pod statuses
kubectl get pods -n online-boutique

# Stream logs from a service
kubectl logs -f deployment/frontend -n online-boutique

# Describe a failing pod
kubectl describe pod <pod-name> -n online-boutique

# Get the frontend external URL
kubectl get svc frontend-external -n online-boutique \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Port-forward the frontend to localhost (no ELB needed)
kubectl port-forward svc/frontend 8080:80 -n online-boutique
# Then open http://localhost:8080

# Check Terraform outputs
cd terraform/environments/dev && terraform output

# Verify OIDC role assumption works (run from a GitLab job or locally with SSO)
aws sts get-caller-identity
```

---

## Teardown

### Via GitLab CI

Trigger the `terraform:destroy` job manually from the pipeline UI. It destroys **all** AWS resources including the EKS cluster, VPC, and ElastiCache (if enabled).

### Manually

```bash
cd terraform/environments/dev   # or prod
terraform destroy
```

> **Note:** The S3 bucket and DynamoDB table created in Part 1 are not managed by Terraform and must be deleted manually if no longer needed.

> **Important:** Running `terraform destroy` also removes the GitLab OIDC provider and IAM role. After a full destroy, the pipeline cannot authenticate until the OIDC module is re-bootstrapped locally: `terraform apply -target=module.gitlab_oidc`. To avoid this, run `terraform destroy` with `-target` on everything *except* the OIDC module, or just use the pipeline's `terraform:destroy` job which preserves the OIDC resources in state.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `terraform init` fails with S3 error | Bucket does not exist or wrong region | Check bucket name and region in `-backend-config` flags |
| `UnauthorizedAccess` during `assume-role-with-web-identity` | OIDC trust policy `sub` condition does not match the pipeline's project path or branch | Check `gitlab_project_path` in the `gitlab-oidc` module and the branch pattern |
| `ERR_EMPTY_RESPONSE` / LoadBalancer exists but no pods | Namespace PSS `restricted` rejected all pods at admission (0 pods, no events) | Namespace enforce level is set to `baseline` in Terraform; if manually overridden run `kubectl label namespace online-boutique pod-security.kubernetes.io/enforce=baseline --overwrite` then `kubectl rollout restart deployment -n online-boutique` |
| Nodes stuck in `NotReady` | VPC-CNI addon not healthy | `kubectl describe nodes` → check events; verify prefix delegation settings |
| Pods in `Pending` (no reason) | Insufficient node capacity | Increase `node_max_size` or use a larger instance type |
| `frontend-external` has no `EXTERNAL-IP` | ELB still provisioning | Wait 2–3 min; check AWS Console → EC2 → Load Balancers |
| `cartservice` `CrashLoopBackOff` | Cannot reach Redis | Verify `redis-cart` pod is running, or confirm ElastiCache endpoint in ConfigMap |
| HPA shows `<unknown>/60%` for CPU or services stuck at 0 replicas | Metrics Server not installed — EKS does **not** include it by default | `kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml` (already included in the `app:deploy` pipeline job) |
| NetworkPolicy blocking unexpected traffic | Default-deny is too strict | `kubectl describe networkpolicy <name> -n online-boutique`; add a policy for the missing path |
| `aws eks update-kubeconfig` fails | Cluster endpoint is private (prod) | Must run from within the VPC (bastion host or VPN) in prod |

