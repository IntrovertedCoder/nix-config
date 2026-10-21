# OpenTofu owns the Incus objects that can be declared: instances, images,
# volumes, networks, the storage pool's settings, the default profile (design
# doc, nix-config & tooling). Run it through the app, never bare `tofu`:
#
#   nix run .#tofu -- plan
#   nix run .#tofu -- apply
#
# The app (modules/cluster/apps/tofu.nix) runs it on a node, as root, against
# that node's Incus socket, with the provider pinned by flake.lock (no
# registry download) and the values below from the flake. The state is kept
# in Ceph (pool `important`, namespace `opentofu`), locked while a run is
# going on, so it doesn't live on any workstation.

terraform {
  required_providers {
    incus = { source = "lxc/incus" }
  }
}

# The node's own Incus, through its local socket: no certificates.
provider "incus" {
  generate_client_certificates = false
}
