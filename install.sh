#! /run/current-system/sw/bin/bash
sudo nix --extra-experimental-features "nix-command flakes" \
  run 'github:nix-community/disko/latest#disko-install' -- \
  --flake .#vmtest \
  --disk main /dev/sda
