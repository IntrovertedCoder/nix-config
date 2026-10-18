{ inputs, lib, ... }: {
  # Tailscale on cluster nodes -- remote access for you, nothing more. The
  # nodes themselves don't depend on it: the `cluster` tool reaches the other
  # nodes over SSH on the mesh (tools.nix), so it works without internet.
  # tailscale.nix (via the terminal module) already enables it and persists
  # /var/lib/tailscale; this only changes what cluster nodes advertise.
  #
  # Login is manual, once per install, until the OAuth secret below exists
  # (the bootstrap scripts refuse to run until it's done):
  #
  #   sudo tailscale up --advertise-tags=tag:cluster
  #
  # Tailnet policy needed (admin console -> Access controls):
  #
  #   "tagOwners": { "tag:cluster": ["autogroup:admin"] },
  #
  # plus, if your policy restricts traffic at all, a rule letting your
  # devices reach tag:cluster on port 20530. No "ssh" section: Tailscale SSH
  # is off on the nodes (--ssh=false below). Being logged into the tailnet
  # isn't a credential -- you log in with regular sshd (port 20530,
  # ~/.ssh/nixos), over the tailnet or the LAN:
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
        # No exit-node routing -- the router VMs take that job later. SSH
        # off explicitly, not just left out: the setting persists in
        # /var/lib/tailscale, and nodes from before this had it on.
        extraSetFlags = lib.mkForce [ "--ssh=false" ];
      }
      (lib.mkIf haveOauth {
        authKeyFile = config.age.secrets.tailscale-cluster-oauth.path;
        # OAuth secrets need the tag on the command line; ephemeral=false so
        # the node isn't removed when it goes offline (e.g. a reboot).
        authKeyParameters = { ephemeral = false; preauthorized = true; };
        extraUpFlags = lib.mkForce [ "--advertise-tags=tag:cluster" ];
      })
    ];
  };
}
