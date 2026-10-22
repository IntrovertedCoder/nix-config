# agenix recipients file. Consumed by the `agenix` CLI (not by the flake
# itself) whenever you run `agenix -e secrets/<name>.age`.
#
# Recipients are host SSH keys, not new user keys -- sshd.nix already
# generates and preserves /etc/ssh/ssh_host_ed25519_key(.pub) on every host,
# and agenix's default age.identityPaths already includes that path, so
# there's nothing new to distribute.
#
# TODO (one-time, before secrets/*.age can be created for real): replace
# the placeholder below with vmtest's actual host key:
#   ssh vmtest cat /etc/ssh/ssh_host_ed25519_key.pub
let
  vmtest = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGXL4eFZvGU76IWAQFGax7+CQgGBmtXkdayHXp92227w root@vmtest";

  # The user key (~/.ssh/nixos), so installs from a workstation can decrypt.
  arik = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdnAXOp0q2Ehf9KwXo2KXOD/UDnam7uyezYnUm1WdnA arik";

  clusterHosts = import ./modules/cluster/_hosts.nix;
  clusterKeys = map (h: h.hostKey) (builtins.attrValues clusterHosts);
in
{
  "secrets/discord-webhook.age".publicKeys = [ arik vmtest ] ++ clusterKeys;
  "secrets/discord-urgent-webhook.age".publicKeys = [ arik vmtest ] ++ clusterKeys;
  "secrets/healthchecks-ping-url.age".publicKeys = [ vmtest ];
  "secrets/cluster-healthchecks-ping-key.age".publicKeys = [ arik ] ++ clusterKeys;

  # Tailscale OAuth client secret (auth keys: write, tag:cluster only) -- lets
  # a freshly installed node join the tailnet on its own. See
  # modules/cluster/tailscale.nix.
  "secrets/tailscale-cluster-oauth.age".publicKeys = [ arik ] ++ clusterKeys;

  # SSH key the `cluster` tool uses to reach shot on the other nodes over the
  # mesh (fd9a:7af:74af:ff::<id>). See modules/cluster/tools.nix.
  "secrets/cluster-ssh-key.age".publicKeys = [ arik ] ++ clusterKeys;

  # The UniFi gear's SSH login (the controller's Device SSH Authentication),
  # "username=..." and "password=..." lines. With it the switch and AP can
  # be pointed at a rebuilt controller (`set-inform`) without a factory
  # reset, which the AP's location makes hard.
  "secrets/unifi-device-ssh.age".publicKeys = [ arik ] ++ clusterKeys;
}
# Each cluster node's SSH host private key, shipped by the cluster-testlab app at
# install. Every node can decrypt every node's key, so any working node can
# rebuild a broken one.
// builtins.listToAttrs (map (name: {
  name = "secrets/hostkeys/${name}.age";
  value.publicKeys = [ arik ] ++ clusterKeys;
}) (builtins.attrNames clusterHosts))
