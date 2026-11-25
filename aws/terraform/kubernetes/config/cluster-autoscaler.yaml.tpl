autoDiscovery:
  clusterName: ${cluster_name}

awsRegion: ${region}

rbac:
  serviceAccount:
    create: true
    name: cluster-autoscaler
    annotations:
      eks.amazonaws.com/role-arn: ${autoscaler_role_arn}

extraArgs:
  balance-similar-node-groups: true
  skip-nodes-with-local-storage: false
  skip-nodes-with-system-pods: false
  # Which node group to grow when a pending pod would fit in more than one.
  # The cluster autoscaler ignores a pod's preferred node affinity, so with
  # the default expander a Smarter pod (which only prefers node-group=smarter)
  # could grow any node group it fits in, e.g. the WordPress group, which is
  # managed outside this repository. "priority" grows the highest-priority
  # group in expanderPriorities below; least-waste breaks ties among groups
  # of equal priority.
  expander: priority,least-waste

# Node groups are matched by their auto scaling group's name; the highest
# number wins. EKS names a managed node group's ASG eks-<node group name>-...,
# so ^eks-smarter- matches this repository's smarter group and every
# environment's stateful group (smarter-<env>-stateful). Every other group
# (WordPress, ...) gets the lowest priority: it grows only for pods that fit
# nowhere else, such as WordPress's, which require node-group=wordpress.
expanderPriorities:
  10:
    - .*
  50:
    - ^eks-smarter-.*

# pulled through the ECR pull-through cache for registry.k8s.io
image:
  repository: ${image_repository}
