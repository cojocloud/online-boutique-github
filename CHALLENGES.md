# Project Challenges & Solutions — Interview Talking Points

A record of real problems encountered while building this project and how each was diagnosed and resolved. Useful for answering "What challenges did you face?" or "Tell me about a time you had to debug a production issue."

---

## 1. Eliminating Long-Lived AWS Credentials with GitLab OIDC

### Challenge
The original pipeline stored `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` as GitLab CI variables. Static IAM credentials are a significant security risk — they never expire, can be leaked through log output or environment variable dumps, and violate the principle of least privilege because they exist outside any job's lifecycle.

### Solution
Replaced static credentials with **GitLab OIDC federation**. Each CI job requests a short-lived JWT (`GITLAB_OIDC_TOKEN`) from GitLab's identity provider, then exchanges it for temporary AWS credentials via `aws sts assume-role-with-web-identity`. The IAM trust policy is scoped to a specific GitLab project path and branch pattern, so only the exact repo and branch can assume the role. Credentials expire when the job ends — no rotation required, no secrets to manage.

### Why It Matters
This is the AWS-recommended approach for CI/CD. It removes an entire category of credential-leak risk and satisfies compliance requirements (SOC 2, ISO 27001) that flag long-lived secrets.

---

## 2. Terraform Modularization — Reusable vs. Flat Code

### Challenge
The original Terraform was a flat collection of files with environment-specific logic hardcoded using string comparisons like `var.environment == "prod"`. This made it impossible to reuse modules across environments without copy-pasting, and any change had to be made in multiple places.

### Solution
Refactored into **four reusable modules** (`vpc`, `eks`, `elasticache`, `gitlab-oidc`) with environment-specific configurations isolated in `environments/dev` and `environments/prod`. Instead of string comparisons inside modules, behaviour is controlled by explicit boolean variables (`single_nat_gateway`, `high_availability`, `cluster_endpoint_public_access`). Each environment has its own Terraform state in S3 (`online-boutique/dev/terraform.tfstate` vs `online-boutique/prod/terraform.tfstate`).

### Why It Matters
True modularity means a module doesn't need to know which environment it's in — the caller decides. This is the difference between reusable infrastructure code and a monolith with conditionals.

---

## 3. GitLab CI — Bash Syntax Not Supported in YAML Fields

### Challenge
After rewriting the pipeline, every job failed at validation with:
```
jobs:terraform:apply:environment name can contain only letters, digits, '-', '_', '/', ...
```
The pipeline used `${TF_VAR_environment:-dev}` (bash default-value syntax) in the `environment.name` field and `variables:` block.

### Root Cause
GitLab CI YAML fields are not processed by a shell — they are parsed directly by the GitLab runner. Bash `${VAR:-default}` syntax is only valid inside `script:` blocks where a real shell is running. Outside of scripts, GitLab's variable interpolation only supports `$VAR` or `${VAR}`, with no fallback syntax.

### Solution
Declared explicit default values in the top-level `variables:` block:
```yaml
variables:
  TF_VAR_environment: "dev"
  TF_VAR_cluster_name: "online-boutique"
```
Then used plain `$TF_VAR_environment` everywhere. GitLab CI/CD variables set at runtime override these defaults, achieving the same fallback behaviour.

### Takeaway
Know the difference between shell variable expansion and the CI platform's own variable interpolation. They look identical but behave differently depending on where in the YAML they appear.

---

## 4. Terraform — IAM `name_prefix` Length Limit

### Challenge
`terraform apply` failed with:
```
Error: expected length of name_prefix to be in the range (1 - 38),
got online-boutique-dev-workers-eks-node-group-
```

### Root Cause
The EKS Terraform module appends `-eks-node-group-` (16 characters) to the node group `name_prefix` when creating IAM resources. The node group was named `"${var.cluster_name}-workers"`, which expanded to `online-boutique-dev-workers` (26 chars). Adding the suffix: `online-boutique-dev-workers-eks-node-group-` = 43 characters, exceeding the 38-character IAM limit.

### Solution
Changed the node group name from `"${var.cluster_name}-workers"` to the fixed string `"workers"`. Result: `workers-eks-node-group-` = 23 characters, well within the limit. The cluster name is already present in the node group's parent resource, so the short name is unambiguous.

### Takeaway
When using community Terraform modules, read the source to understand what suffixes they append to resource names. IAM name limits are easy to hit when combining cluster name + role suffix + module-appended suffix.

---

## 5. IAM Role Creation — Hidden ASCII Constraint on Description Field

### Challenge
`terraform apply` failed with:
```
ValidationError: Value at 'description' failed to satisfy constraint:
Member must satisfy regular expression pattern: [\u0009\u000A\u000D\u0020-\u007E\u00A1-\u00FF]*
```

### Root Cause
The IAM role description contained an **em dash** (`—`, U+2014), which falls outside the allowed ASCII range (`\u0020-\u007E`). The character looks identical to a regular hyphen in most editors and was copied in from documentation.

### Solution
Replaced the em dash with a plain hyphen (`-`). The error message's Unicode range hint was the key — `\u0020-\u007E` is the standard printable ASCII range, and U+2014 falls outside it.

### Takeaway
AWS API field validation errors include the regex pattern. Read the pattern to identify exactly which character is invalid rather than guessing. Hidden Unicode characters (em dashes, smart quotes, non-breaking spaces) are a common source of cryptic validation failures.

---

## 6. Kustomize — Binary Name Conflicts with Directory Name

### Challenge
Running `kustomize build kustomize/` from the project root failed with:
```
Error: must build at directory: not a valid directory:
evalsymlink failure on 'kustomize/' : lstat .../kustomize/kustomize: no such file or directory
```

### Root Cause
The `kustomize` binary on the `$PATH` and the `kustomize/` directory share the same base name. When the tool resolved the path, it looked for a binary named `kustomize` inside the `kustomize/` directory rather than treating `kustomize/` as the build target directory.

### Solution
Use an explicit relative path prefix: `./kustomize/` instead of `kustomize/`. The `./` makes the argument unambiguously a filesystem path, bypassing `$PATH` resolution entirely.

### Takeaway
When a tool and a directory share a name, the shell and path resolution can behave unexpectedly. Always use `./` for relative paths when ambiguity is possible.

---

## 7. Kustomize — Security Boundary Blocking Cross-Directory Resources

### Challenge
After fixing the path, a second error appeared:
```
Error: accumulating resources: security; file '.../kubernetes/manifests.yaml'
is not in or below '.../kustomize'
```

### Root Cause
Kustomize enforces a security boundary by default: resources referenced in `kustomization.yaml` must live within or below the build directory. Our `kustomization.yaml` lived in `kustomize/` but referenced `../kubernetes/manifests.yaml` (a parent directory). Kustomize blocks this by default to prevent path traversal attacks.

### Solution
Pass the `--load-restrictor=LoadRestrictionsNone` flag to explicitly opt out of the restriction. The flag takes a camelCase enum value — not a boolean or lowercase string.

### Takeaway
Security tools often have opt-out flags rather than opt-in flags for restrictions. When you need cross-directory resource loading, understand *why* the restriction exists before bypassing it — in this case it's safe because we control both directories.

---

## 8. Kustomize — Flag Value is a CamelCase Enum, Not a String

### Challenge
After discovering the `--load-restrictor` flag, running:
```bash
kustomize build --load-restrictor=none ./kustomize/
```
failed with:
```
Error: illegal flag value --load-restrictor none;
legal values: [LoadRestrictionsRootOnly LoadRestrictionsNone]
```

### Root Cause
The flag value is a Go-style enum (`LoadRestrictionsNone`), not a freeform string. Passing `none` (lowercase) is not a valid enum member.

### Solution
```bash
kustomize build --load-restrictor=LoadRestrictionsNone ./kustomize/
```

### Takeaway
CLI tools backed by Go enums are case-sensitive. When a tool gives you `legal values: [...]`, use the exact casing shown — don't assume lowercase will work.

---

## 9. Pod Security Standards — `restricted` Silently Blocking All Pods

### Challenge
Kustomize reported a successful apply, the frontend-external LoadBalancer was provisioned and had a hostname, but the app returned `ERR_EMPTY_RESPONSE`. Running `kubectl get pods -n online-boutique` returned:
```
No resources found in online-boutique namespace.
```
The namespace existed, the deployments and services were created, but there were zero pods.

### Root Cause
The EKS namespace was labelled with `pod-security.kubernetes.io/enforce: restricted`. The `restricted` Pod Security Standard requires every container to explicitly set `runAsNonRoot`, `seccompProfile`, `allowPrivilegeEscalation: false`, and drop all Linux capabilities. The Online Boutique demo containers don't include these security contexts, so the Kubernetes admission controller silently rejected every pod creation request. The Deployments and ReplicaSets existed, but every attempt to schedule a pod was denied at admission — no events surfaced in the rollout status because the rejection happened before any pod object was created.

### Solution
Changed enforcement to `baseline`, which blocks genuine privilege-escalation vectors (host namespaces, privileged containers) without requiring explicit security contexts on every container. Kept `audit=restricted` and `warn=restricted` so violations still appear in logs and kubectl warnings — useful for tracking what would need to change to reach full `restricted` compliance.

```bash
kubectl label namespace online-boutique \
  pod-security.kubernetes.io/enforce=baseline \
  pod-security.kubernetes.io/warn=restricted \
  --overwrite
```

### Takeaway
`restricted` PSS is the right long-term goal but requires workloads to be hardened before enforcing. Start with `baseline` enforce + `restricted` warn/audit — you get meaningful security guarantees immediately and a clear signal of what needs fixing to reach the stricter standard. The `ERR_EMPTY_RESPONSE` pattern (LB endpoint works, no pods exist) is the diagnostic signature of PSS admission rejection.

---

## 10. HPA Stuck at Zero — Metrics-Server Not Installed

### Challenge
After fixing the PSS enforcement level, 5 deployments (frontend, cartservice, checkoutservice, productcatalogservice, recommendationservice) remained at 0 pods even though the namespace now allowed them. The other services came up fine. Events showed:
```
Warning FailedGetResourceMetric horizontalpodautoscaler/frontend
failed to get cpu utilization: unable to fetch metrics from resource metrics API:
the server could not find the requested resource (get pods.metrics.k8s.io)
```

### Root Cause
The Horizontal Pod Autoscaler requires **metrics-server** to read CPU utilization from pods. EKS does not install metrics-server by default — it must be added separately. Without it, the HPA enters a permanent error state.

The compounding factor: these pods had initially been rejected by PSS `restricted` (0 pods). Once the HPA took ownership of the replica count, it set `spec.replicas` on the deployment. With metrics-server absent, the HPA couldn't compute desired replicas and left the deployments stuck at 0 — even after PSS was relaxed to `baseline`.

### Solution
Install metrics-server:
```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```
Once metrics-server was available, the HPAs recovered and scaled each deployment up to `minReplicas`.

### Takeaway
HPA is not self-contained — it has an external dependency on metrics-server that must be explicitly installed. When HPA and PSS failures compound (PSS rejects pods → HPA sees 0 pods → HPA can't get metrics → HPA stays at 0), the symptoms look like a single problem but require two separate fixes applied in order.

---

## 11. Rollout Restart Needed After Namespace Label Change

### Challenge
After changing the namespace PSS label from `restricted` to `baseline`, the blocked deployments still showed `0/1` and `0/2`. No new pods appeared even though the enforcement policy had been relaxed.

### Root Cause
The ReplicaSet controller had already attempted pod creation, received admission rejections, and applied exponential backoff. It does not automatically retry when a namespace label changes — there is no watch/reconcile loop that triggers on namespace label updates. The ReplicaSets were silently waiting out their backoff timers while the namespace label had already been fixed.

### Solution
```bash
kubectl rollout restart deployment -n online-boutique
```
This creates new ReplicaSets for every deployment, which immediately attempt pod creation under the current (now relaxed) admission policy. The `Warning: would violate PodSecurity "restricted:latest"` messages printed during the restart are non-blocking — they come from the `warn=restricted` label and are informational only.

### Takeaway
Changing a namespace admission policy does not retroactively unblock stuck ReplicaSets. Always follow a namespace label change with `kubectl rollout restart deployment` to force the controllers to re-evaluate pod admission under the new policy.

---

## 12. Pipeline Stuck in Pending — No Runner Available

### Challenge
After pushing to GitLab, the pipeline sat in `pending` status indefinitely. Checking **Settings → CI/CD → Runners** showed: *"No project runners found."*

### Root Cause
Two separate issues combined:
1. GitLab shared runners were not enabled for the project (off by default on some plans/projects).
2. The pipeline had `tags: [docker]` in the `default:` block, which restricts every job to runners tagged `docker`. GitLab's shared runners don't carry that tag, so even after enabling shared runners, every job was skipped.

### Solution
- Enabled shared runners in **Settings → CI/CD → Runners → Enable shared runners for this project**.
- Removed the `tags: [docker]` block from `default:` in `.gitlab-ci.yml` so jobs can run on any available runner.

### Takeaway
`tags:` in a CI config is a runner selector, not a Docker flag. If you don't have a self-hosted runner registered with that exact tag, every job silently waits forever. When a pipeline is stuck in `pending`, check runner availability and tag matching before investigating the job config itself.

---

## 13. AWS CLI Not Bundled in the GitLab Terraform Image

### Challenge
After fixing the runner issue, the `terraform:plan` job failed immediately with:
```
/bin/sh: eval: line 199: aws: not found
ERROR: Job failed: exit code 127
```

### Root Cause
The default CI image (`registry.gitlab.com/gitlab-org/terraform-images/stable:latest`) ships only with Terraform and Git — it does not include the AWS CLI. The OIDC credential exchange `before_script` calls `aws sts assume-role-with-web-identity` as its very first command, which fails instantly on a system without `aws`.

### Solution
Added `apk add --no-cache aws-cli` as the first step in the `terraform_before` anchor's `before_script`, before the assume-role script runs:
```yaml
before_script:
  - apk add --no-cache aws-cli   # image is Alpine-based; aws-cli is in the apk registry
  - *assume_role
  - cd "${TF_ROOT}"
  ...
```

### Takeaway
Always verify which tools are pre-installed in a CI base image before writing scripts that depend on them. The GitLab Terraform image is purpose-built for Terraform — anything else (AWS CLI, kubectl, jq) must be installed explicitly. `exit code 127` in a shell script always means "command not found", which narrows the search immediately.

---

## 16. OIDC Bootstrap Chicken-and-Egg — Pipeline Can't Authenticate After `terraform destroy`

### Challenge
After running `terraform destroy` locally to clean up manually-provisioned infrastructure, the pipeline immediately failed on every job with:
```
An error occurred (InvalidIdentityToken) when calling the AssumeRoleWithWebIdentity operation:
No OpenIDConnect provider found in your account for https://gitlab.com
ERROR: Job failed: exit code 254
```

### Root Cause
The GitLab OIDC federation depends on two AWS resources — an `aws_iam_openid_connect_provider` and an `aws_iam_role` — that were created by the `gitlab-oidc` Terraform module. When `terraform destroy` removed all infrastructure, it also removed these two resources. The pipeline now has no OIDC provider to authenticate against, so every job fails at the credential exchange step before it can run any Terraform to recreate itself.

This is a true chicken-and-egg: the pipeline needs the OIDC provider to authenticate → but the OIDC provider was destroyed → and only the pipeline (or a local apply) can recreate it.

### Solution
Re-bootstrap the OIDC module locally using your own AWS credentials. Only the `gitlab-oidc` module needs to be restored — the pipeline can provision the rest of the infrastructure itself once authentication works again:

```bash
cd terraform/environments/dev

terraform init \
  -backend-config="bucket=<TF_STATE_BUCKET>" \
  -backend-config="region=<AWS_DEFAULT_REGION>" \
  -backend-config="dynamodb_table=<TF_LOCK_TABLE>"

terraform apply \
  -target=module.gitlab_oidc \
  -var="aws_region=<AWS_DEFAULT_REGION>" \
  -var="gitlab_project_path=<GITLAB_PROJECT_PATH>" \
  -var="tf_state_bucket=<TF_STATE_BUCKET>" \
  -var="tf_lock_table=<TF_LOCK_TABLE>"
```

After this completes, verify the IAM role ARN still matches `CI_AWS_ROLE_ARN` in GitLab Settings → CI/CD → Variables, then re-run the pipeline.

### Takeaway
The OIDC provider and IAM role are prerequisites for the pipeline — they are infrastructure that enables the pipeline, not infrastructure the pipeline manages. Treat them as a one-time bootstrap: apply them locally once, then never include them in a `terraform destroy` sweep. Using `-target=module.gitlab_oidc` on both apply and destroy makes this boundary explicit.

---

## 17. IAM Permissions Discovered Incrementally — KMS and CloudWatch Logs

### Challenge
`terraform:apply` failed with two `AccessDeniedException` errors on the same run:
```
kms:TagResource ... is not authorized to perform: kms:TagResource
logs:ListTagsForResource ... is not authorized to perform: logs:ListTagsForResource
```
The original `gitlab-oidc` IAM policy had a `KMSReadForTerraformPlan` statement covering only read actions (`DescribeKey`, `ListKeys`, etc.) and a `CloudWatchLogs` statement missing the newer `ListTagsForResource`/`TagResource` API methods.

### Root Cause
The IAM policy was written to cover what `terraform plan` needs (read-only) but not what `terraform apply` needs (write operations). The EKS community module creates a KMS key for secrets encryption and calls `kms:TagResource` to tag it. The CloudWatch Logs module uses the newer `logs:ListTagsForResource` API (replacing the deprecated `logs:ListTagsLogGroup`) which wasn't in the policy.

### Solution
Expanded the `KMSReadForTerraformPlan` statement (renamed in spirit to cover full lifecycle) to include write actions:
```
kms:CreateKey, kms:EnableKeyRotation, kms:PutKeyPolicy, kms:TagResource,
kms:UntagResource, kms:ScheduleKeyDeletion, kms:CreateAlias, kms:DeleteAlias, kms:UpdateAlias
```
Added missing CloudWatch Logs actions:
```
logs:ListTagsForResource, logs:TagResource, logs:UntagResource
```
Then ran `terraform apply -target=module.gitlab_oidc -auto-approve` locally to push the updated policy to AWS before re-running the pipeline.

### Takeaway
IAM policies for CI/CD need to cover **apply-time** permissions, not just plan-time. A `terraform plan` only reads current state; `terraform apply` creates, tags, and configures resources. When using community modules, review the module source to understand every AWS API call it makes — not just the resource types it creates.

---

## 18. Tainted Resource Causing `ResourceAlreadyExistsException`

### Challenge
After fixing the IAM permissions, `terraform:apply` failed again with:
```
ResourceAlreadyExistsException: The specified log group already exists
  with module.eks.module.eks.aws_cloudwatch_log_group.this[0]
```
Attempting to import the resource returned `Resource already managed by Terraform`. Running a fresh pipeline still failed with the same error.

### Root Cause
A previous `terraform:apply` run (the one that failed due to missing IAM permissions) had partially succeeded — it created the CloudWatch log group in AWS before the job failed. Terraform recorded the resource as **tainted** in the state, meaning it was created but the apply didn't complete cleanly. On the next apply, Terraform's plan for a tainted resource is to destroy-then-recreate it. The destroy succeeded, but the recreate hit `ResourceAlreadyExistsException` because the old log group still existed in AWS (destroy hadn't fully propagated, or a race condition occurred).

### Solution
```bash
terraform untaint 'module.eks.module.eks.aws_cloudwatch_log_group.this[0]'
```
This told Terraform the resource is healthy and should not be replaced. A fresh pipeline then generated a plan that saw the log group as an existing, in-sync resource and skipped it.

### Takeaway
A tainted resource is Terraform's way of flagging "I created this but something went wrong — recreate it next apply." When the resource already exists in AWS and is functioning correctly, `terraform untaint` is the right fix. Always check for tainted resources (`terraform state list` + `terraform state show`) before re-running a failed apply.

---

## 19. Route53 `ListTagsForResource` — Missing Permission on Hosted Zone Lookup

### Challenge
The `dns:apply` pipeline job failed during planning:
```
AccessDenied: ... is not authorized to perform: route53:ListTagsForResource
on resource: arn:aws:route53:::hostedzone/Z09634432V4R01XN9AQK7
```
This occurred on the `data "aws_route53_zone" "parent"` data source — just looking up the hosted zone, not modifying it.

### Root Cause
The AWS Terraform provider calls `route53:ListTagsForResource` internally when reading a hosted zone, even for a read-only `data` source. The Route53DNS IAM policy statement only included the actions explicitly listed in the Terraform docs (`GetHostedZone`, `ListHostedZones`, `ChangeResourceRecordSets`, etc.) but missed this implicit API call made by the provider's SDK.

### Solution
Added `route53:ListTagsForResource` to the `Route53DNS` IAM policy statement, then ran `terraform apply -target=module.gitlab_oidc -auto-approve` to push the update.

### Takeaway
Terraform provider resource/data source implementations often make additional API calls beyond what the documentation lists — particularly for tagging and metadata. When you get an `AccessDenied` on a read-only data source, it's almost always an undocumented SDK call. Check the provider's GitHub source or simply add the `ListTagsForResource` equivalent for that service.

---

## Summary Table

| # | Problem | Root Cause | Fix |
|---|---------|------------|-----|
| 1 | Static AWS credentials | Long-lived IAM keys in CI variables | GitLab OIDC federation — short-lived STS tokens |
| 2 | Unmaintainable Terraform | Flat files with hardcoded env logic | Reusable modules + per-environment roots |
| 3 | GitLab CI YAML error | Bash `${VAR:-default}` in non-script field | Declare defaults in top-level `variables:` block |
| 4 | IAM name_prefix too long | Module appends suffix, exceeds 38-char limit | Use short fixed node group name (`"workers"`) |
| 5 | IAM CreateRole failed | Em dash (U+2014) outside allowed ASCII range | Replace with plain hyphen |
| 6 | Kustomize path resolution | Binary name shadows directory name | Use `./kustomize/` explicit relative path |
| 7 | Kustomize security boundary | Cross-directory resource reference blocked by default | `--load-restrictor=LoadRestrictionsNone` |
| 8 | Kustomize illegal flag value | Flag takes Go enum, not lowercase string | `LoadRestrictionsNone` (camelCase) |
| 9 | Zero pods, LB unreachable | `restricted` PSS rejected pods at admission | Change enforce to `baseline`, keep warn/audit at `restricted` |
| 10 | HPA services stuck at 0 pods | Metrics-server not installed; HPA can't compute replicas | `kubectl apply` metrics-server; HPA recovers automatically |
| 11 | Pods didn't recover after label fix | ReplicaSet backoff doesn't reset on namespace label change | `kubectl rollout restart deployment -n online-boutique` |
| 12 | Pipeline stuck in pending forever | Shared runners disabled + `tags: [docker]` excluded all runners | Enable shared runners; remove `tags:` block from `default:` |
| 13 | `aws: not found` in Terraform job | AWS CLI not bundled in GitLab Terraform image | `apk add --no-cache aws-cli` in `before_script` |
| 14 | `CI_AWS_ROLE_ARN` empty despite being set | Variable marked "Protected"; not injected into non-protected branches | Uncheck "Protected" on the variable or protect the branch |
| 15 | IAM roleSessionName validation error | `CI_JOB_NAME` contains `:` (e.g. `terraform:plan`); colon not in `[\w+=,.@-]*` | Sanitize with `tr ':' '-'` before passing to `--role-session-name` |
| 16 | `InvalidIdentityToken` after `terraform destroy` | `terraform destroy` removed the OIDC provider + IAM role the pipeline needs to authenticate | Re-bootstrap `module.gitlab_oidc` locally with `-target`; never destroy the OIDC module |
| 17 | `AccessDenied: kms:TagResource` and `logs:ListTagsForResource` during apply | IAM policy covered plan-time reads but not apply-time writes needed by EKS community module | Expand KMS + CloudWatch Logs statements to cover full resource lifecycle; apply `-target=module.gitlab_oidc` |
| 18 | `ResourceAlreadyExistsException` on CloudWatch log group | Partial apply left resource tainted; next apply tried destroy-recreate but hit existing resource | `terraform untaint` the resource; fresh pipeline saw it as healthy and skipped creation |
| 19 | `route53:ListTagsForResource` denied on `data` source lookup | AWS provider calls `ListTagsForResource` internally when reading a hosted zone, even read-only | Add `route53:ListTagsForResource` to Route53DNS IAM statement; apply `-target=module.gitlab_oidc` |
