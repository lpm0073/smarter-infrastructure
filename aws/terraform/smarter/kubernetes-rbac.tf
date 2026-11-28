#------------------------------------------------------------------------------
# usage:      Smarter app infrastructure - the cluster-wide reads of this
#             environment's ServiceAccounts: "smarter", which every pod ran
#             as before smarter ADR-038 phase 3, and one per kind of pod,
#             smarter-<pod>, below.
#
# The Smarter Helm chart gives the ServiceAccount a Role in its namespace
# (helm/charts/smarter/templates/rbac.yaml), and creates nothing outside it,
# so that each environment deploys with namespace-scoped permissions (see
# iam-deploy.tf). These reads are cluster-wide, so they are created here:
# the namespace check, nodes (LLMHost capacity, cluster status),
# PersistentVolumes (the inventory) and node metrics. It is the same
# ClusterRole that the chart creates with serviceAccount.createClusterRole.
#------------------------------------------------------------------------------

resource "kubernetes_cluster_role_v1" "smarter" {
  metadata {
    name = "smarter-${local.environment_namespace}"
    labels = {
      "app.kubernetes.io/name"              = "smarter"
      "app.kubernetes.io/application-group" = "smarter"
    }
  }

  rule {
    api_groups     = [""]
    resources      = ["namespaces"]
    resource_names = [local.environment_namespace]
    verbs          = ["get"]
  }

  rule {
    api_groups = [""]
    resources  = ["nodes", "persistentvolumes"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["metrics.k8s.io"]
    resources  = ["nodes"]
    verbs      = ["get", "list"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "smarter" {
  metadata {
    name = "smarter-${local.environment_namespace}"
    labels = {
      "app.kubernetes.io/name"              = "smarter"
      "app.kubernetes.io/application-group" = "smarter"
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.smarter.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = "smarter"
    namespace = local.environment_namespace
  }

  # the local environment's Docker containers (iam-local.tf)
  dynamic "subject" {
    for_each = local.is_local_environment ? [local.local_docker_kubernetes_group] : []
    content {
      api_group = "rbac.authorization.k8s.io"
      kind      = "Group"
      name      = subject.value
    }
  }
}

#------------------------------------------------------------------------------
# One ClusterRole per kind of pod (smarter ADR-038, phase 3, smarter#1084)
#
# Each kind of pod runs as its own ServiceAccount, smarter-<pod>, with only the
# cluster-wide reads that its code does, the same that the chart's
# templates/rbac.yaml creates with serviceAccount.createClusterRole:
#
# - api: its namespace, nodes and node metrics (LLMHost capacity, the staff
#   platform_status tool);
# - worker: its namespace, when it starts;
# - worker-infrastructure and job-init: its namespace, nodes and
#   PersistentVolumes (LLMHost capacity, the inventory).
#
# The ClusterRole above, bound to the ServiceAccount "smarter", stays until
# every environment runs a chart with these ServiceAccounts: the pods that a
# rollout hasn't replaced yet still run as "smarter".
#------------------------------------------------------------------------------
locals {
  smarter_namespace_rule = {
    api_groups     = [""]
    resources      = ["namespaces"]
    resource_names = [local.environment_namespace]
    verbs          = ["get"]
  }
  smarter_nodes_rule = {
    api_groups     = [""]
    resources      = ["nodes"]
    resource_names = []
    verbs          = ["get", "list"]
  }
  smarter_volumes_rule = {
    api_groups     = [""]
    resources      = ["persistentvolumes"]
    resource_names = []
    verbs          = ["get", "list"]
  }
  smarter_node_metrics_rule = {
    api_groups     = ["metrics.k8s.io"]
    resources      = ["nodes"]
    resource_names = []
    verbs          = ["get", "list"]
  }
  smarter_pod_cluster_rules = {
    "api"                   = [local.smarter_namespace_rule, local.smarter_nodes_rule, local.smarter_node_metrics_rule]
    "worker"                = [local.smarter_namespace_rule]
    "worker-infrastructure" = [local.smarter_namespace_rule, local.smarter_nodes_rule, local.smarter_volumes_rule]
    "job-init"              = [local.smarter_namespace_rule, local.smarter_nodes_rule, local.smarter_volumes_rule]
  }
}

resource "kubernetes_cluster_role_v1" "smarter_pod" {
  for_each = local.smarter_pod_cluster_rules

  metadata {
    name = "smarter-${local.environment_namespace}-${each.key}"
    labels = {
      "app.kubernetes.io/name"              = "smarter-${each.key}"
      "app.kubernetes.io/application-group" = "smarter"
    }
  }

  dynamic "rule" {
    for_each = each.value
    content {
      api_groups     = rule.value.api_groups
      resources      = rule.value.resources
      resource_names = rule.value.resource_names
      verbs          = rule.value.verbs
    }
  }
}

resource "kubernetes_cluster_role_binding_v1" "smarter_pod" {
  for_each = local.smarter_pod_cluster_rules

  metadata {
    name = "smarter-${local.environment_namespace}-${each.key}"
    labels = {
      "app.kubernetes.io/name"              = "smarter-${each.key}"
      "app.kubernetes.io/application-group" = "smarter"
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.smarter_pod[each.key].metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = "smarter-${each.key}"
    namespace = local.environment_namespace
  }
}
