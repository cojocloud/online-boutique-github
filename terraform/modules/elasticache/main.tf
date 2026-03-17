resource "aws_elasticache_subnet_group" "this" {
  name       = "${var.cluster_name}-redis-subnet-group"
  subnet_ids = var.private_subnet_ids
}

resource "aws_security_group" "this" {
  name        = "${var.cluster_name}-redis-sg"
  description = "Allow Redis traffic from EKS worker nodes only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Redis from EKS worker nodes"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [var.node_security_group_id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id = "${var.cluster_name}-redis-cart"
  description          = "Redis cache for Online Boutique cart service"

  node_type            = var.node_type
  engine_version       = "7.1"
  parameter_group_name = "default.redis7"
  port                 = 6379

  # HA mode: 2 replicas + Multi-AZ failover. Controlled by var.high_availability.
  # Set high_availability = true in prod for resilience against AZ failure.
  num_cache_clusters         = var.high_availability ? 2 : 1
  automatic_failover_enabled = var.high_availability
  multi_az_enabled           = var.high_availability

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [aws_security_group.this.id]

  at_rest_encryption_enabled = true
  # transit_encryption_enabled = false: cartservice connects without TLS by default;
  # set to true and update REDIS_ADDR to use rediss:// when hardening for prod.
  transit_encryption_enabled = false

  # 7-day snapshots in HA mode for point-in-time recovery; 1 day otherwise
  snapshot_retention_limit = var.high_availability ? 7 : 1

  # Defer changes to maintenance window in HA mode to avoid mid-traffic restarts
  apply_immediately = !var.high_availability
}
