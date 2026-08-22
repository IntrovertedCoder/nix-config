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
in
{
  "secrets/discord-webhook.age".publicKeys = [ vmtest ];
  "secrets/healthchecks-ping-url.age".publicKeys = [ vmtest ];
}
