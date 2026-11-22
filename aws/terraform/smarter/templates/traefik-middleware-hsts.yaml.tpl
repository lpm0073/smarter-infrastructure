######################################################################
# Traefik Middleware: HTTP Strict Transport Security (HSTS)
#
# This YAML template defines a Traefik Middleware that adds the
# Strict-Transport-Security header to every HTTPS response.
#
# Purpose:
#   - Tell browsers to use only HTTPS for this host, for sts_seconds.
#     A browser that has seen the header upgrades a typed http:// URL
#     or an old http:// link to HTTPS itself, before anything is sent,
#     so an attacker on the network can't intercept that first plain
#     HTTP request.
#   - Traefik terminates TLS, so it adds the header here, in one place
#     for every host, the deployed chatbots and custom domains included.
#     Django's SECURE_HSTS_SECONDS stays unset. Django learns the scheme
#     only from the X-Forwarded-Proto header that Traefik sets
#     (SECURE_PROXY_SSL_HEADER in smarter's settings/base_aws.py).
#
# Caution:
#   - A browser keeps the promise for the whole max-age, whatever the
#     server does later. Raise sts_seconds only once HTTPS has been
#     reliable at the current value, and never add includeSubDomains
#     or preload without checking every subdomain: deployed chatbots
#     and custom domains live under the platform's domains.
#
# Template Variables:
#   - ${environment_namespace}: Namespace where the middleware is deployed.
#   - ${sts_seconds}: The header's max-age, in seconds.
#
# Usage:
#   - Reference this middleware in your Traefik router annotations,
#     as ingress.yaml.tpl does.
#
# For more information, see:
#   https://doc.traefik.io/traefik/reference/routing-configuration/http/middlewares/headers/
#   https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Strict-Transport-Security
######################################################################
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: hsts
  namespace: ${environment_namespace}
  labels:
      app.kubernetes.io/application-group: ${ app_name }
      app.kubernetes.io/name: ${ app_name }
spec:
  headers:
    stsSeconds: ${sts_seconds}
    stsIncludeSubdomains: false
    stsPreload: false
