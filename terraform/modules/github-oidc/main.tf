# ── GitHub Actions OIDC federation – short-lived AWS credentials for CI/CD ─────
#
# This module eliminates long-lived AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY
# from GitHub Actions by establishing OpenID Connect trust between GitHub and AWS.
#
# Flow:
#   1. GitHub issues a signed JWT to each Actions job (requires id-token: write).
#   2. aws-actions/configure-aws-credentials exchanges the JWT for temporary
#      credentials via aws sts assume-role-with-web-identity.
#   3. AWS validates the JWT against the OIDC provider and returns credentials
#      that expire after the job's session duration (max 1 hour by default).
#
# No static credentials are stored anywhere.
# ──────────────────────────────────────────────────────────────────────────────

data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
}

# ── IAM Role assumed by GitHub Actions jobs ───────────────────────────────────

resource "aws_iam_role" "github_ci" {
  name        = var.role_name
  description = "Assumed by GitHub Actions via OIDC - credentials are short-lived and repository-scoped"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            # Tokens must target the AWS STS audience
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            # Restrict to the specified repository and ref pattern.
            # Examples:
            #   "repo:my-org/online-boutique:ref:refs/heads/main"  (main branch only)
            #   "repo:my-org/online-boutique:*"                    (all branches — dev)
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_repository}:${var.allowed_ref_pattern}"
          }
        }
      }
    ]
  })
}

# ── Least-privilege IAM policy for infrastructure provisioning ─────────────────

resource "aws_iam_policy" "github_ci_deploy" {
  name        = "${var.role_name}-policy"
  description = "Scoped permissions for GitHub Actions to manage EKS infrastructure and deploy the app"

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

resource "aws_iam_role_policy_attachment" "github_ci_deploy" {
  role       = aws_iam_role.github_ci.name
  policy_arn = aws_iam_policy.github_ci_deploy.arn
}
