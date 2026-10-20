# OpenTofu owns the Incus objects that can be declared: instances, images,
# volumes, networks, the storage pool's settings, the default profile (design
# doc, nix-config & tooling). Run it through the app, never bare `tofu`:
#
#   nix run .#tofu -- plan
#   nix run .#tofu -- apply
#
# The app (modules/cluster/apps/tofu.nix) supplies the provider (pinned by
# flake.lock, no registry download), tunnels to Incus's API on the mesh over
# SSH through a healthy node, and passes the values below.
#
# State is local (terraform.tfstate here, gitignored): back it up by hand.

terraform {
  required_providers {
    incus = { source = "lxc/incus" }
  }
}

variable "incus_address" {
  description = "Incus API through the app's SSH tunnel (https://127.0.0.1:<port>)."
  type        = string
}

variable "incus_config_dir" {
  description = "Client certificate and pinned server certificate (~/.config/elements-tofu)."
  type        = string
}

provider "incus" {
  config_dir                   = var.incus_config_dir
  generate_client_certificates = false # the app makes it and gets it trusted
  accept_remote_certificate    = true  # pinned on first use, checked after
  default_remote               = "elements"

  remote {
    name    = "elements"
    address = var.incus_address
  }
}
