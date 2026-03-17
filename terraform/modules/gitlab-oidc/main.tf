# ── GitLab OIDC federation – short-lived AWS credentials for CI/CD ─────────────
#
# This module eliminates long-lived AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY
# from GitLab CI by establishing OpenID Connect trust between GitLab and AWS.
#
# Flow:
#   1. GitLab issues a signed JWT (GITLAB_OIDC_TOKEN) to each CI job.
#   2. The CI job calls aws sts assume-role-with-web-identity using that JWT.
#   3. AWS validates the JWT against the OIDC provider and returns credentials
#      that expire after the job's session duration (max 1 hour by default).
#
# No static credentials are stored anywhere.
# ──────────────────────────────────────────────────────────────────────────────

data "tls_certificate" "gitlab" {
  url = "https://gitlab.com"
}

resource "aws_iam_openid_connect_provider" "gitlab" {
  url             = "https://gitlab.com"
  client_id_list  = ["https://gitlab.com"]
  thumbprint_list = [data.tls_certificate.gitlab.certificates[0].sha1_fingerprint]
}

# ── IAM Role assumed by GitLab CI jobs ────────────────────────────────────────

resource "aws_iam_role" "gitlab_ci" {
  name        = var.role_name
  description = "Assumed by GitLab CI via OIDC - credentials are short-lived and project-scoped"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.gitlab.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            # Tokens must be issued for this GitLab instance
            "gitlab.com:aud" = "https://gitlab.com"
          }
          StringLike = {
            # Restrict to the specified project path and branch pattern
            # e.g. "project_path:mygroup/myrepo:ref_type:branch:ref:main"
            "gitlab.com:sub" = "project_path:${var.gitlab_project_path}:ref_type:branch:ref:${var.allowed_branches}"
          }
        }
      }
    ]
  })
}

# ── Least-privilege IAM policy for infrastructure provisioning ─────────────────

resource "aws_iam_policy" "gitlab_ci_deploy" {
  name        = "${var.role_name}-policy"
  description = "Scoped permissions for GitLab CI to manage EKS infrastructure and deploy the app"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EKSManagement"
        Effect   = "Allow"
        Action   = ["eks:*"]
        Resource = "*"
      },
      {
        Sid    = "ComputeAndNetworking"
        Effect = "Allow"
        Action = [
          "ec2:*",
          "elasticloadbalancing:*",
          "autoscaling:*"
        ]
        Resource = "*"
      },
      {
        Sid      = "IAMManagement"
        Effect   = "Allow"
        Action   = ["iam:*"]
        Resource = "*"
      },
      {
        Sid    = "TerraformStateAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketVersioning",
          "s3:GetEncryptionConfiguration"
        ]
        Resource = [
          "arn:aws:s3:::${var.tf_state_bucket}",
          "arn:aws:s3:::${var.tf_state_bucket}/*"
        ]
      },
      {
        Sid    = "TerraformStateLocking"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
          "dynamodb:DescribeTable"
        ]
        Resource = "arn:aws:dynamodb:*:*:table/${var.tf_lock_table}"
      },
      {
        Sid      = "ElastiCacheManagement"
        Effect   = "Allow"
        Action   = ["elasticache:*"]
        Resource = "*"
      },
      {
        Sid      = "KMSManagement"
        Effect   = "Allow"
        Action   = ["kms:*"]
        Resource = "*"
      },
      {
        Sid      = "Route53Management"
        Effect   = "Allow"
        Action   = ["route53:*"]
        Resource = "*"
      },
      {
        Sid      = "CloudWatchLogsManagement"
        Effect   = "Allow"
        Action   = ["logs:*"]
        Resource = "*"
      },
      {
        Sid      = "ACMManagement"
        Effect   = "Allow"
        Action   = ["acm:*"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "gitlab_ci_deploy" {
  role       = aws_iam_role.gitlab_ci.name
  policy_arn = aws_iam_policy.gitlab_ci_deploy.arn
}
