#------------------------------------------------------------------------------
# CloudWatch alarms on the stateful node (node-group-stateful.tf): CPU, memory
# and root disk.
#
# MariaDB, Redis and Loki share this one node, and the taint keeps them off
# every other. If it runs short of memory or disk, the kubelet evicts pods (or
# the kernel's OOM killer ends one), and a single-replica database goes down.
# These alarms warn before that happens:
#
# - memory: mem_used_percent above 85% for 10 minutes. The kubelet starts
#   evicting at 100 MiB available, about 97% of a t3.medium.
# - disk: disk_used_percent of / above 80% for 10 minutes. The kubelet starts
#   deleting unused images at 85%, and evicts pods at 90%.
# - cpu: CPUUtilization above 80% for 15 minutes. A t3's baseline is 20% of
#   each vCPU, and the node runs in unlimited mode, so a long stretch above
#   that is billed as surplus credits before it's ever throttled.
#
# Where the numbers come from. CPUUtilization is EC2's own metric (5-minute
# basic monitoring, free). Memory and disk come from the CloudWatch agent that
# the node's user data installs (templates/stateful-node-cloudwatch-agent.sh).
# Every alarm watches the node group's Auto Scaling group rather than an
# instance id, so it keeps working when EKS replaces the node.
#
# Each alarm emails the SNS topic below when it fires and when it clears. The
# memory and disk alarms also email when their metric stops arriving
# (INSUFFICIENT_DATA): the agent failed to install or stopped.
#
# The topic is in this environment's region, with the alarms and the EC2 and
# agent metrics. The uptime alarms' topic (uptime.tf) is in us-east-1, where
# Route 53 publishes its metrics, so it can't be shared. Both email
# var.uptime_alert_email, so that address gets two confirmation emails.
#
# Cost: about $0.90/month for three agent metrics, $0.45/month for the agent's
# PutMetricData calls, and $0.10/month per alarm: under $2/month.
#
# Technical documentation:
# - https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-Agent-Configuration-File-Details.html
# - https://kubernetes.io/docs/concepts/scheduling-eviction/node-pressure-eviction/
#------------------------------------------------------------------------------

locals {
  # The node group's one Auto Scaling group.
  stateful_node_group_asg = var.stateful_node_group_enabled ? one(module.stateful_node_group[0].node_group_autoscaling_group_names) : null

  stateful_node_alarms = var.stateful_node_group_enabled ? {
    cpu = {
      description        = "CPU use of the ${local.environment_namespace} stateful node (MariaDB, Redis, Loki) is above 80%"
      namespace          = "AWS/EC2"
      metric_name        = "CPUUtilization"
      threshold          = 80
      period             = 300
      evaluation_periods = 3
      # EC2 always reports CPU while the instance runs.
      notify_on_missing = false
    }
    memory = {
      description        = "memory use of the ${local.environment_namespace} stateful node (MariaDB, Redis, Loki) is above 85%, or the CloudWatch agent stopped reporting it"
      namespace          = "CWAgent"
      metric_name        = "mem_used_percent"
      threshold          = 85
      period             = 60
      evaluation_periods = 10
      notify_on_missing  = true
    }
    disk = {
      description        = "root disk use of the ${local.environment_namespace} stateful node (MariaDB, Redis, Loki) is above 80%, or the CloudWatch agent stopped reporting it"
      namespace          = "CWAgent"
      metric_name        = "disk_used_percent"
      threshold          = 80
      period             = 60
      evaluation_periods = 10
      notify_on_missing  = true
    }
  } : {}
}

resource "aws_sns_topic" "stateful_node" {
  count = var.stateful_node_group_enabled ? 1 : 0

  name = "${local.environment_namespace}-stateful-node"
  tags = local.tags
}

# As in uptime.tf: AWS emails a confirmation link, and sends nothing until
# somebody clicks it.
resource "aws_sns_topic_subscription" "stateful_node_email" {
  count = (var.stateful_node_group_enabled && var.uptime_alert_email != "") ? 1 : 0

  topic_arn = aws_sns_topic.stateful_node[0].arn
  protocol  = "email"
  endpoint  = var.uptime_alert_email
}

resource "aws_cloudwatch_metric_alarm" "stateful_node" {
  for_each = local.stateful_node_alarms

  alarm_name        = "${local.environment_namespace}-stateful-node-${each.key}"
  alarm_description = each.value.description

  namespace   = each.value.namespace
  metric_name = each.value.metric_name
  dimensions = {
    AutoScalingGroupName = local.stateful_node_group_asg
  }

  # Every period in the window must average above the threshold, so a short
  # spike, such as a backup or an image pull, doesn't notify anybody.
  statistic           = "Average"
  period              = each.value.period
  evaluation_periods  = each.value.evaluation_periods
  comparison_operator = "GreaterThanThreshold"
  threshold           = each.value.threshold

  # Missing datapoints don't count either way. While a node is replaced, the
  # old and new ones are briefly in the same Auto Scaling group, so the metric
  # doesn't stop. A whole window without data moves the alarm to
  # INSUFFICIENT_DATA.
  treat_missing_data = "missing"

  alarm_actions             = [aws_sns_topic.stateful_node[0].arn]
  ok_actions                = [aws_sns_topic.stateful_node[0].arn]
  insufficient_data_actions = each.value.notify_on_missing ? [aws_sns_topic.stateful_node[0].arn] : []

  tags = local.tags
}
