#!/bin/bash
#------------------------------------------------------------------------------
# cloud-init part of the stateful node's user data (node-group-stateful.tf):
# installs the CloudWatch agent, which publishes the node's memory and root
# disk use to CloudWatch every minute. EC2 reports CPU on its own, but it can't
# see inside the instance, so without this the alarms in
# node-group-stateful-alarms.tf would have nothing to watch.
#
# Metrics, in the CWAgent namespace:
# - mem_used_percent   memory in use, not counting page cache and buffers
# - disk_used_percent  the root filesystem (/), which holds container images,
#                      container logs and emptyDir volumes. The services' own
#                      data is on their EBS volumes, not here.
#
# Each metric is also aggregated by AutoScalingGroupName alone, which stays the
# same when EKS replaces the node, so the alarms keep working across upgrades
# and node repairs. omit_hostname keeps a new metric (billed separately) from
# being created for every new node.
#
# Best effort: this runs before nodeadm joins the node to the cluster, and a
# monitoring failure must not keep the node out of it. If the install fails,
# the alarms go to INSUFFICIENT_DATA, which notifies the same SNS topic.
#
# This file is not a Terraform template: ${aws:AutoScalingGroupName} is the
# agent's own placeholder, which it fills in from the instance's tags.
#------------------------------------------------------------------------------

if ! dnf install -y amazon-cloudwatch-agent; then
  echo "stateful-node-cloudwatch-agent: dnf install failed; the node runs without the CloudWatch agent" >&2
  exit 0
fi

CONFIG=/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
cat >"$CONFIG" <<'EOF'
{
  "agent": {
    "metrics_collection_interval": 60,
    "omit_hostname": true
  },
  "metrics": {
    "append_dimensions": {
      "AutoScalingGroupName": "${aws:AutoScalingGroupName}"
    },
    "aggregation_dimensions": [["AutoScalingGroupName"]],
    "metrics_collected": {
      "mem": {
        "measurement": ["mem_used_percent"]
      },
      "disk": {
        "measurement": ["used_percent"],
        "resources": ["/"],
        "drop_device": true
      }
    }
  }
}
EOF

# -s starts the agent and enables its systemd unit, so it survives a reboot.
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -s -c "file:$CONFIG" ||
  echo "stateful-node-cloudwatch-agent: the agent failed to start" >&2

exit 0
