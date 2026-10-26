# Which Incus instances count as down: a jq filter over `incus list -f json`
# that passes the instances that should be running and aren't. Shared by
# elements-health (healthchecks.nix) and cluster debug's Attention list
# (tools.nix), so the alert and the report always agree; cluster vm-debug
# spells out the same rule for one instance. Plain data (the leading
# underscore keeps import-tree from loading it as a flake module).
#
# Any instance, so new services are covered. Incus keeps
# volatile.last_state.power at RUNNING when an instance dies with its node,
# STOPPED when you stop it yourself; Incus can't read the state while the
# node is down, so any status but Running, Stopped or Frozen -- Error,
# Offline -- counts as down too.
''select(.status != "Running" and (.config["volatile.last_state.power"] == "RUNNING" or (.status != "Stopped" and .status != "Frozen")))''
