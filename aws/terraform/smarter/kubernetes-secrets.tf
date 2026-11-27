#------------------------------------------------------------------------------
# written by: Lawrence McDaniel
#             https://lawrencemcdaniel.com/
#
# date:       July-2023
#
# usage:      Smarter app infrastructure - create Kubernetes secrets for the
#             Smarter app. These include:
#             - MySQL root credentials
#             - MySQL credentials for the Smarter app
#             - Admin credentials for the Smarter app
#             - Django secret key for the Smarter app
#             - Redis password for the Smarter app
#------------------------------------------------------------------------------

#--------------------------------------------------------------
# Deploy containerized application to an existing Kubernetes cluster
#--------------------------------------------------------------

# resource "kubernetes_manifest" "deployment" {
#   manifest = yamldecode(data.template_file.deployment.rendered)
# }

# 3. horizontal scaling policy
# 4. vertical scaling policy
# 9. mysql secret
resource "random_password" "mysql_root" {
  length           = 16
  special          = true
  override_special = "_%@"
  keepers = {
    version = "1"
  }
}

resource "kubernetes_secret_v1" "mysql_root" {
  metadata {
    name      = "mysql-root"
    namespace = local.environment_namespace
  }

  data = {
    MYSQL_ROOT_USERNAME = var.mysql_root_username
    MYSQL_ROOT_PASSWORD = var.mysql_root_password
    MYSQL_HOST          = var.mysql_host
    MYSQL_PORT          = var.mysql_port
  }

  depends_on = [kubernetes_namespace_v1.smarter]
}



resource "random_password" "mysql_smarter" {
  length           = 16
  special          = true
  override_special = "_%@"
  keepers = {
    version = "1"
  }
}

resource "kubernetes_secret_v1" "mysql_smarter" {
  metadata {
    name      = "mysql-smarter"
    namespace = local.environment_namespace
  }

  data = {
    SMARTER_MYSQL_DATABASE = local.mysql_database
    SMARTER_MYSQL_USERNAME = local.mysql_username
    SMARTER_MYSQL_PASSWORD = random_password.mysql_smarter.result
    MYSQL_HOST             = var.mysql_host
    MYSQL_PORT             = var.mysql_port
  }

  depends_on = [kubernetes_namespace_v1.smarter]
}

resource "random_password" "smarter_admin_password" {
  length           = 16
  special          = true
  override_special = "_%@"
  keepers = {
    version = "1"
  }
}

resource "kubernetes_secret_v1" "smarter_admin_password" {
  metadata {
    name      = "smarter-admin"
    namespace = local.environment_namespace
  }

  data = {
    SMARTER_ADMIN_USERNAME = "admin"
    SMARTER_ADMIN_PASSWORD = random_password.smarter_admin_password.result
  }

  depends_on = [kubernetes_namespace_v1.smarter]
}


resource "random_password" "django_secret_key" {
  length           = 16
  special          = true
  override_special = "_%@"
  keepers = {
    version = "1"
  }
}

resource "kubernetes_secret_v1" "django_secret_key" {
  metadata {
    name      = "smarter-django-secret-key"
    namespace = local.environment_namespace
  }

  data = {
    SECRET_KEY = random_password.django_secret_key.result
  }

  depends_on = [kubernetes_namespace_v1.smarter]
}

# The password of the environment's Redis: the Celery broker, the cache and the sessions.
# The Smarter Helm chart reads it twice from this Secret (infrastructureSecrets): its Redis
# subchart sets it as Redis's password (auth.existingSecret), and the platform's pods build
# their Redis urls from it (SMARTER_SUBSYSTEM_REDIS_PASSWORD). Until this Secret existed, the
# password was the chart's public default, "smarter" (smarter ADR-030, rule 5).
#
# Letters and digits only: the pods put it in a redis:// url, where % and @ would break the
# url's parsing. It is longer than the passwords above to make up for that.
#
# The Secret isn't named smarter-redis: the Redis subchart's fullnameOverride is
# smarter-redis, and Bitnami's chart creates a Secret of that name when it isn't given one.
resource "random_password" "redis" {
  length  = 32
  special = false
  keepers = {
    version = "1"
  }
}

resource "kubernetes_secret_v1" "redis" {
  metadata {
    name      = "smarter-redis-password"
    namespace = local.environment_namespace
  }

  data = {
    REDIS_PASSWORD = random_password.redis.result
  }

  depends_on = [kubernetes_namespace_v1.smarter]
}
