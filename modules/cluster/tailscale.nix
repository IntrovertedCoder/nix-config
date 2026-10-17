{ inputs, lib, ... }: {
  # Tailscale on cluster nodes. tailscale.nix (via the terminal module)
  # already enables it and persists /var/lib/tailscale; this only changes
  # what cluster nodes advertise.
  #
  # Login is manual, once per install (cluster-testlab.sh reminds you, and
  # the bootstrap scripts refuse to run until it's done):
  #
  #   sudo tailscale up --ssh --advertise-tags=tag:cluster
  #
  # Tailnet policy needed (admin console -> Access controls):
  #
  #   "tagOwners": { "tag:cluster": ["autogroup:admin"] },
  #   "ssh": [
  #     { "action": "accept",
  #       "src":   ["tag:cluster"],
  #       "dst":   ["tag:cluster"],
  #       "users": ["shot"] }
  #   ]
  #
  # plus, if your policy restricts traffic at all,
  #   { "action": "accept", "src": ["tag:cluster"], "dst": ["tag:cluster:*"] }
  #
  # Only the nodes themselves may Tailscale-SSH to each other -- that's what
  # the `cluster` tool (debug / restore / replace-osd) uses, as shot;
  # anything needing root goes through sudo with shot's password. Personal
  # devices are deliberately not in "src": being logged into the tailnet
  # isn't a credential. They use regular sshd (port 20530, ~/.ssh/nixos):
  #
  #   ssh -p 20530 shot@test-node1 cluster debug
  #
  # Automatic login: once secrets/tailscale-cluster-oauth.age exists (an
  # OAuth client secret limited to creating tag:cluster auth keys, see
  # secrets.nix), a freshly installed node joins the tailnet on its own at
  # first boot -- it decrypts the secret with its pre-seeded host key. Until
  # the file exists, login stays manual (the command above).
  flake.nixosModules.clusterTailscale = { config, lib, ... }: let
    oauthSecret = ../../secrets/tailscale-cluster-oauth.age;
    haveOauth = builtins.pathExists oauthSecret;
  in {
    imports = [ inputs.agenix.nixosModules.default ];

    age.secrets = lib.optionalAttrs haveOauth {
      tailscale-cluster-oauth.file = oauthSecret;
    };

    # nixpkgs orders the auto-login after tailscaled only; on a fresh boot it
    # ran before DHCP had given us DNS, failed to resolve api.tailscale.com
    # and gave up (seen in the rebuild test). Wait for the network, and
    # retry rather than strand a freshly installed node.
    systemd.services.tailscaled-autoconnect = lib.mkIf haveOauth {
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = { Restart = "on-failure"; RestartSec = 10; };
      unitConfig.StartLimitIntervalSec = 0;
    };

    services.tailscale = lib.mkMerge [
      {
        # Tailscale SSH instead of exit-node routing -- the router VMs take
        # that job later.
        extraSetFlags = lib.mkForce [ "--ssh" ];
      }
      (lib.mkIf haveOauth {
        authKeyFile = config.age.secrets.tailscale-cluster-oauth.path;
        # OAuth secrets need the tag on the command line; ephemeral=false so
        # the node isn't removed when it goes offline (e.g. a reboot).
        authKeyParameters = { ephemeral = false; preauthorized = true; };
        extraUpFlags = lib.mkForce [ "--ssh" "--advertise-tags=tag:cluster" ];
      })
    ];
  };
}
