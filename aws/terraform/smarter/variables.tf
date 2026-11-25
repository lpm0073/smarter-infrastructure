#------------------------------------------------------------------------------
# written by: Lawrence McDaniel
#             https://lawrencemcdaniel.com/
#
# date:       July-2023
#
# usage:      Smarter app infrastructure - Terraform variable declarations
#------------------------------------------------------------------------------
variable "shared_resource_identifier" {
  description = "A common identifier/prefix for resources created for this demo"
  type        = string
  default     = "openai"
}

variable "aws_account_id" {
  description = "12-digit AWS account number"
  type        = string
}
variable "aws_region" {
  description = "A valid AWS data center region code"
  type        = string
  default     = "us-east-1"
}

variable "tags" {
  description = "A map of tags to add to all resources. Tags added to launch configuration or templates override these values."
  type        = map(string)
  default     = {}
}

variable "root_domain" {
  description = "a valid Internet domain name which you directly control using AWS Route53 in this account"
  type        = string
  default     = "smarter.sh"
}

variable "platform_name" {
  description = "the name of the platform (e.g. smarter)"
  type        = string
  default     = "smarter"
}
variable "platform_subdomain" {
  description = "a valid Internet domain name which you directly control using AWS Route53 in this account"
  type        = string
  default     = "alpha"
}

variable "platform_domain" {
  description = "a valid Internet domain name which you directly control using AWS Route53 in this account"
  type        = string
  default     = "platform.smarter.sh"
}

variable "platform_api_domain" {
  description = "a valid Internet domain name which you directly control using AWS Route53 in this account"
  type        = string
  default     = "api.platform.smarter.sh"
}

variable "environment" {
  description = "the environment name (e.g. local, alpha, beta, next, prod)"
  type        = string
  default     = "local"
}

variable "environment_name" {
  description = "the environment name prefixed with the stack name (e.g. smarter-alpha)"
  type        = string
}

variable "install_metrics_server" {
  description = "install metrics-server, which the cluster's HPAs need. One per cluster: set true in exactly one environment that shares it"
  type        = bool
  default     = false
}

variable "stateful_node_group_enabled" {
  description = "create this environment's stateful node group: one ON_DEMAND node, tainted and labeled smarter.sh/node-pool=stateful, for MariaDB, Redis and Loki (node-group-stateful.tf)"
  type        = bool
  default     = false
}

variable "stateful_node_group_availability_zone" {
  description = "availability zone of the stateful node group, e.g. ca-central-1b. It must be the zone of the EBS volumes of the services that run on it. Changing it replaces the node group"
  type        = string
  default     = ""

  validation {
    condition     = !var.stateful_node_group_enabled || var.stateful_node_group_availability_zone != ""
    error_message = "stateful_node_group_availability_zone is required when stateful_node_group_enabled is true."
  }
}

variable "stateful_node_group_instance_types" {
  description = "instance types of the stateful node group. Changing them replaces the node group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "uptime_alert_email" {
  description = "email address that receives this environment's uptime alarms (uptime.tf) and stateful node alarms (node-group-stateful-alarms.tf). Empty: the alarms are created, but nobody is notified"
  type        = string
  default     = ""
}

variable "cluster_name" {
  description = "name of the existing EKS cluster"
  type        = string
}

variable "mysql_host" {
  description = "hostname of the existing MySQL database"
  type        = string
}

variable "mysql_port" {
  description = "port number of the existing MySQL database"
  type        = string
  default     = "3306"
}

variable "mysql_root_username" {
  description = "root username of the existing MySQL database"
  type        = string
  default     = "root"
}
variable "mysql_root_password" {
  description = "root password of the existing MySQL database"
  type        = string
}
