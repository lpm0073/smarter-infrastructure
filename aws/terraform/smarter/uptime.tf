#------------------------------------------------------------------------------
# usage:      Smarter app infrastructure - uptime monitoring of this
#             environment's platform and api hosts.
#
# Route 53 health checkers in several AWS regions request
# https://<host>/readiness/ every 30 seconds. /readiness/ goes through Django
# and its middleware (see the readinessProbe in smarter's Helm chart), so a
# 200 means the whole path works: DNS, the load balancer, Traefik, the
# smarter-api service and at least one ready pod. A host is unhealthy after
# 3 consecutive failures, as most checkers see it.
#
# Each health check publishes HealthCheckStatus (1 = up, 0 = down) to
# CloudWatch, and an alarm on that metric emails the SNS topic below, both when
# the host goes down and when it recovers. Route 53's metrics exist only in
# us-east-1, so the alarms and the topic are created there, whatever
# var.aws_region is. The health checks themselves are global.
#
# Cost: about $0.75/month per health check (a non-AWS endpoint, as far as
# Route 53 is concerned) plus $1/month for HTTPS, so about $3.50/month per
# environment for both hosts, plus $0.10/month per alarm. String matching
# would add $1/month per check; the status code is enough here.
#
# Not in the local environment: its hosts aren't served by this cluster (see
# route53.tf).
#------------------------------------------------------------------------------

locals {
  uptime_hosts = local.is_local_environment ? {} : {
    platform = local.environment_platform_domain
    api      = local.environment_api_domain
  }
}

resource "aws_route53_health_check" "uptime" {
  for_each = local.uptime_hosts

  fqdn              = each.value
  port              = 443
  type              = "HTTPS"
  resource_path     = "/readiness/"
  failure_threshold = 3
  request_interval  = 30

  # Sends the hostname in the TLS handshake, so Traefik presents this host's
  # certificate instead of its default one.
  enable_sni = true

  tags = merge(local.tags, { Name = "${local.environment_namespace}-${each.key}" })
}

resource "aws_sns_topic" "uptime" {
  count    = local.is_local_environment ? 0 : 1
  provider = aws.us-east-1

  name = "${local.environment_namespace}-uptime"
  tags = local.tags
}

# AWS emails the address a confirmation link, and sends nothing until somebody
# clicks it. Until then the subscription shows as "pending confirmation" and
# Terraform can't delete it; AWS removes it after 3 days if it isn't confirmed.
resource "aws_sns_topic_subscription" "uptime_email" {
  count    = (local.is_local_environment || var.uptime_alert_email == "") ? 0 : 1
  provider = aws.us-east-1

  topic_arn = aws_sns_topic.uptime[0].arn
  protocol  = "email"
  endpoint  = var.uptime_alert_email
}

resource "aws_cloudwatch_metric_alarm" "uptime" {
  for_each = local.uptime_hosts
  provider = aws.us-east-1

  alarm_name        = "${local.environment_namespace}-${each.key}-down"
  alarm_description = "https://${each.value}/readiness/ is failing Route 53 health checks"

  namespace   = "AWS/Route53"
  metric_name = "HealthCheckStatus"
  dimensions = {
    HealthCheckId = aws_route53_health_check.uptime[each.key].id
  }

  # Down for two consecutive minutes. Together with the health check's own
  # failure_threshold, an outage is reported about 2-3 minutes after it starts,
  # and a single slow response or a rolling deploy doesn't page anybody.
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 2
  comparison_operator = "LessThanThreshold"
  threshold           = 1

  # No data means Route 53 stopped reporting, which is as bad as a failure.
  treat_missing_data = "breaching"

  alarm_actions = [aws_sns_topic.uptime[0].arn]
  ok_actions    = [aws_sns_topic.uptime[0].arn]

  tags = local.tags
}
