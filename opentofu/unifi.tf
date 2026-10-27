# The old UniFi controller, a NixOS container running UniFi Network Server,
# was replaced by UniFi OS Server (unifi-os.tf) at the switch. Its image and
# instance are gone; its data volume stays a few weeks as the way back
# (`git revert` the switch commit and apply: design doc, "Finish the move").
# Then remove prevent_destroy, apply to delete it, and remove this file.

resource "incus_storage_volume" "unifi_data" {
  name         = "unifi-data"
  # The pool resource, not its name: a fresh cluster creates both in one
  # apply, and the volume has to wait for the pool (found in the first
  # fresh build).
  pool         = incus_storage_pool.remote.name
  content_type = "filesystem"
  config = {
    size = "10GiB"
    # Ceph snapshots: undo a bad update or a wrong click. (Losing Ceph is
    # what the nodes' daily copy of UniFi's own backups is for.)
    "snapshots.schedule" = "@daily"
    "snapshots.expiry"   = "2w"
    "snapshots.pattern"  = "daily-{{ creation_date|date:'2006-01-02' }}"
  }

  # The old controller's whole state (MongoDB, settings, backups).
  lifecycle { prevent_destroy = true }
}
