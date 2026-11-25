#------------------------------------------------------------------------------
# The stateful node group: one ON_DEMAND node for this environment's
# single-replica stateful services (MariaDB, Redis and Loki).
#
# Every other node in the cluster is SPOT. AWS reclaims a spot node with two
# minutes' notice, and a pod with a ReadWriteOnce EBS volume can't start
# anywhere else until the volume has detached from the old node and attached
# to the new one. For MariaDB, Redis and Loki, each a single pod, every
# reclaim was an outage of 1.5 to 14 minutes (smarter-sh/smarter issue #942). An on-demand
# node is never reclaimed, so these pods move only when an operator upgrades
# or replaces this node group, at a time they choose.
#
# How pods get here. The node carries a label and a taint, both under the key
# smarter.sh/node-pool (local.stateful_node_pool below):
#
# - the taint keeps every other pod off the node, so the stateful services
#   always find room on it;
# - a pod that tolerates the taint and prefers the label (a preferred node
#   affinity, not a required one) is scheduled here when the node is up, and
#   on a spot node when it isn't, rather than staying Pending.
#
# The smarter Helm chart defines that toleration and affinity once, as the
# YAML anchors statefulNodePoolTolerations and statefulNodePoolAffinity in
# helm/charts/smarter/values.yaml, and MariaDB, Redis and Loki reference them.
# Another service with the same need joins by referencing the same anchors.
# Keep the key and value here and there in step.
#
# One availability zone. An EBS volume can't leave its zone, and the node
# group runs in exactly one: the zone that holds the services' volumes
# (stateful_node_group_availability_zone). A service whose volume is in
# another zone can't use this node until its volume is moved.
#
# Sizing. MariaDB, Redis and Loki together use under 400 MiB of memory and
# well under a tenth of a vCPU. A t3.medium (2 vCPU, 4 GiB, about 3.4 GiB of it
# allocatable) holds them with room to spare, provided that their resource
# requests in the chart stay near what they use: the scheduler places pods by
# their requests, not by their use. t3 is burstable: its baseline is 20% of
# each vCPU, and EKS launch templates run it in "unlimited" mode, so a long
# spike is billed as surplus credits (CloudWatch CPUSurplusCreditsCharged)
# rather than throttled. Changing instance_types replaces the node group.
#
# Upgrades proceed on their own. For an AMI or Kubernetes version update, EKS
# starts a new node in the same subnet, then drains the old one. The chart's
# PodDisruptionBudgets (maxUnavailable: 1) let the drain evict the pods, which
# start on the new node after their volumes move: an outage of a minute or two
# per service. Run upgrades at a quiet time. Nothing else evicts these pods:
# their cluster-autoscaler.kubernetes.io/safe-to-evict annotation stops the
# cluster autoscaler, and the descheduler protects every pod with a PVC.
#
# Naming. The node group is <environment_name>-stateful-<suffix>. It must not
# start with smarter-<environment>-, the prefix of the LLMHost node groups that
# the platform's own IAM policy may create and delete (iam-irsa.tf).
#
# Technical documentation:
# - https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest/submodules/eks-managed-node-group
# - https://docs.aws.amazon.com/eks/latest/userguide/managed-node-groups.html
# - https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/
#------------------------------------------------------------------------------

locals {
  # The label and taint that mark the stateful node pool. The smarter Helm
  # chart's values.yaml uses the same key and value.
  stateful_node_pool = {
    key   = "smarter.sh/node-pool"
    value = "stateful"
  }
}

# The node security group that the kubernetes stack's EKS module creates for
# every node group, with the cluster's node-to-node and control plane rules.
# Its Name tag is "<cluster name>-node"; its real name has a generated suffix.
data "aws_security_group" "eks_node" {
  count  = var.stateful_node_group_enabled ? 1 : 0
  vpc_id = data.aws_eks_cluster.eks.vpc_config[0].vpc_id

  filter {
    name   = "tag:Name"
    values = ["${var.cluster_name}-node"]
  }
}

# The VPC's subnets in the node group's availability zone.
data "aws_subnets" "stateful_node_group" {
  count = var.stateful_node_group_enabled ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [data.aws_eks_cluster.eks.vpc_config[0].vpc_id]
  }
  filter {
    name   = "availability-zone"
    values = [var.stateful_node_group_availability_zone]
  }
}

# Lets the node pull images through the ECR pull-through cache. The kubernetes
# stack owns this policy; renaming it there breaks this lookup.
data "aws_iam_policy" "ecr_pull_through_cache" {
  count = var.stateful_node_group_enabled ? 1 : 0
  name  = "${var.cluster_name}-ecr-pull-through-cache"
}

# Lets the CloudWatch agent on the node (templates/stateful-node-cloudwatch-agent.sh)
# publish its metrics, and nothing else. AWS's CloudWatchAgentServerPolicy
# would also grant CloudWatch Logs and SSM Parameter Store, which this agent
# doesn't use. PutMetricData can't be scoped to a resource, only to a
# namespace. DescribeTags is how the agent learns the node's Auto Scaling group
# name; it can't be scoped at all.
data "aws_iam_policy_document" "stateful_node_cloudwatch_agent" {
  count = var.stateful_node_group_enabled ? 1 : 0

  statement {
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = ["CWAgent"]
    }
  }
  statement {
    actions   = ["ec2:DescribeTags"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "stateful_node_cloudwatch_agent" {
  count = var.stateful_node_group_enabled ? 1 : 0

  name        = "${local.environment_namespace}-stateful-node-cloudwatch-agent"
  description = "Lets the CloudWatch agent on the ${local.environment_namespace} stateful node publish memory and disk metrics"
  policy      = data.aws_iam_policy_document.stateful_node_cloudwatch_agent[0].json
  tags        = var.tags
}

module "stateful_node_group" {
  count  = var.stateful_node_group_enabled ? 1 : 0
  source = "terraform-aws-modules/eks/aws//modules/eks-managed-node-group"
  # The version that the kubernetes stack's EKS module and the WordPress node
  # group run. Upgrade deliberately: a new version can change the launch
  # template, and a new launch template version replaces the node.
  version = "21.18.0"

  cluster_name         = data.aws_eks_cluster.eks.name
  kubernetes_version   = data.aws_eks_cluster.eks.version
  cluster_endpoint     = data.aws_eks_cluster.eks.endpoint
  cluster_auth_base64  = data.aws_eks_cluster.eks.certificate_authority[0].data
  cluster_service_cidr = data.aws_eks_cluster.eks.kubernetes_network_config[0].service_ipv4_cidr

  # A name prefix, to which AWS adds a timestamp. The IAM role's name prefix
  # may be at most 38 characters, so it's set here rather than left to the
  # module's default of <name>-eks-node-group-.
  name          = "${var.environment_name}-stateful"
  iam_role_name = "${var.environment_name}-stateful"

  # ON_DEMAND: never reclaimed. Changing capacity_type replaces the node group.
  capacity_type  = "ON_DEMAND"
  instance_types = var.stateful_node_group_instance_types
  min_size       = 1
  max_size       = 1
  desired_size   = 1

  # The cluster's private subnet in the volumes' zone. one() fails the plan
  # if the zone has more than one, rather than spreading the node over them.
  subnet_ids = [one(setintersection(
    data.aws_subnets.stateful_node_group[0].ids,
    data.aws_eks_cluster.eks.vpc_config[0].subnet_ids,
  ))]

  # Detailed (1-minute) CloudWatch monitoring is billed per instance.
  enable_monitoring = false

  # EKS replaces the node if it fails its health checks.
  node_repair_config = {
    enabled = true
  }

  # A rolling update replaces the one node: EKS starts the new node first,
  # then drains the old one (see "Upgrades proceed on their own" above).
  update_config = {
    max_unavailable = 1
  }

  block_device_mappings = {
    xvda = {
      device_name = "/dev/xvda"
      ebs = {
        volume_type           = "gp3"
        volume_size           = 20
        delete_on_termination = true
      }
    }
  }

  vpc_security_group_ids = [data.aws_security_group.eks_node[0].id]

  # Without this policy, the node can pull images already in the ECR
  # pull-through cache, but not the first pull of a new one, which ECR reports
  # as "not found".
  iam_role_additional_policies = {
    ECRPullThroughCache = data.aws_iam_policy.ecr_pull_through_cache[0].arn
    CloudWatchAgent     = aws_iam_policy.stateful_node_cloudwatch_agent[0].arn
  }

  # Installs the CloudWatch agent, for the memory and disk alarms in
  # node-group-stateful-alarms.tf. It runs before nodeadm joins the node to
  # the cluster. A change to this script is a new launch template version,
  # which replaces the node (see "Upgrades proceed on their own" above).
  cloudinit_pre_nodeadm = [
    {
      content_type = "text/x-shellscript; charset=\"us-ascii\""
      content      = file("${path.module}/templates/stateful-node-cloudwatch-agent.sh")
    }
  ]

  labels = {
    (local.stateful_node_pool.key) = local.stateful_node_pool.value
  }

  # NoSchedule: only pods that tolerate it are scheduled here. DaemonSets
  # (aws-node, kube-proxy, the EBS CSI node, Calico) tolerate every taint.
  taints = {
    stateful = {
      key    = local.stateful_node_pool.key
      value  = local.stateful_node_pool.value
      effect = "NO_SCHEDULE"
    }
  }

  tags = merge(
    var.tags,
    {
      Name = "eks-${var.environment_name}-stateful"
    },
  )
}
