# Fleet update automation: verification checklist

Companion to `~/.claude/plans/mutable-chasing-avalanche.md` (the design) and
PR branch `worktree-fleet-update-automation` (the implementation). Work
through this top to bottom on the real `vmtest`/`alaptop` machines — each
step assumes the previous ones passed.

## Testing before Thursday/Friday

Every piece here is a plain `systemd.service`, and the `systemd.timer`
units just schedule *when* that service starts automatically. You can
always run the underlying service on demand, any day, with:

```
systemctl start <name>.service
```

That's exactly what steps 12, 8, and (via the plain command) 15 below do
— none of this waits for `OnCalendar` to fire. You can also confirm the
timer itself is parsed correctly without waiting for it:

```
systemctl list-timers fleet-update.timer      # on vmtest
```

---

## 0. Get the code onto both machines

1. Merge (or fast-forward pull) branch `worktree-fleet-update-automation`
   into whatever `alaptop`/`vmtest` build from.
2. On **both** machines:
   ```
   cd ~/nix-config && git pull
   ```

## 1. Secrets (agenix)

3. Get vmtest's real SSH host pubkey and paste it into `secrets.nix`,
   replacing `REPLACE-WITH-VMTEST-SSH-HOST-PUBKEY`:
   ```
   ssh vmtest cat /etc/ssh/ssh_host_ed25519_key.pub
   ```
4. Create the Discord webhook secret for real:
   ```
   agenix -e secrets/discord-webhook.age
   ```
   (paste your Discord webhook URL, save, exit editor)
5. Create the healthchecks.io secret for real (create a check-in on
   healthchecks.io first if you haven't):
   ```
   agenix -e secrets/healthchecks-ping-url.age
   ```
6. Rebuild vmtest so the secrets actually decrypt (a one-off `switch` is
   fine for this manual step):
   ```
   ssh vmtest 'cd ~/nix-config && sudo nixos-rebuild switch --flake .#vmtest'
   ```
7. Confirm notifications actually work:
   ```
   ssh vmtest notify-discord "test"
   ```
   → check Discord for the message.

## 2. Harmonia signing key

8. On vmtest, place the private key file (delivered separately, not in
   git) and lock it down:
   ```
   sudo mkdir -p /persistent/harmonia
   sudo mv vmtest-1.secret /persistent/harmonia/vmtest-1.secret
   sudo chown root:root /persistent/harmonia/vmtest-1.secret
   sudo chmod 0400 /persistent/harmonia/vmtest-1.secret
   ```
   Delete any other local copies of `vmtest-1.secret` once it's there.

## 3. Boot confirmation / dead-man's-switch

9. Trigger it manually on vmtest:
   ```
   ssh vmtest sudo systemctl start fleet-boot-confirm.service
   ssh vmtest journalctl -u fleet-boot-confirm.service -n 20 --no-pager
   ```
   → confirm a check-in lands on the healthchecks.io dashboard and a
   Discord message shows up.

## 4. Cache server + client

10. Rebuild vmtest with `cache-server.nix` live (same command as step 6),
    then confirm harmonia is actually serving:
    ```
    ssh vmtest curl -sf http://localhost:5000/nix-cache-info
    ```
11. From `alaptop`, confirm the Tailscale-scoped firewall rule actually
    admits it:
    ```
    ssh alaptop curl -sf http://vmtest:5000/nix-cache-info
    ```
12. Rebuild `alaptop` once to pick up `cache-client.nix`'s substituter
    config, then confirm it substitutes instead of compiling:
    ```
    ssh alaptop 'cd ~/nix-config && nix build .#nixosConfigurations.vmtest.config.system.build.toplevel --dry-run'
    ```
    → look for "will be fetched" (cache hit) vs. "will be built" (miss)
    in the output.

## 5. vmtest's weekly cycle — manual trigger

13. Run it by hand right now, no need to wait for Thursday:
    ```
    ssh vmtest sudo systemctl start fleet-update.service
    ssh vmtest journalctl -u fleet-update.service -f
    ```
    Watch for: the git-pull step, `nh os boot --update` succeeding, the
    per-host build/cache-warm loop with a Discord notice per host, and
    the final `flake.lock` commit+push.
14. Verify the "must have latest GitHub commit" fix actually works: make
    a trivial commit from another machine and push it, then re-run step
    13 and confirm vmtest picks it up (check `git log -1` on vmtest
    afterward).
15. Confirm the `flake.lock` push actually reached GitHub (this is the
    step that needs vmtest's `~/.ssh/github` key to have real push
    access):
    ```
    ssh vmtest 'cd ~/nix-config && git log -1 --oneline'
    ```
    then check the same commit shows up on GitHub.

## 6. Follower pull — manual trigger

16. On `alaptop`, since `var.fleet.autoUpdate.enable` is off by default,
    there's no systemd service to start — just run the command directly
    (or use the `n p` yazi keybind):
    ```
    fleet-pull-update
    ```
    Since vmtest already built alaptop's config in step 13, this should
    pull fast (cache hit) and reboot into the right generation.

## 7. Retention

17. Confirm the widened retention window took effect:
    ```
    ssh vmtest nh clean --dry-run
    ```
    (or the real flag `nh` uses in your version — check `nh clean --help`)
    → confirm it doesn't prune a generation you still wanted.

## 8. Go live

18. Once every step above has worked by hand at least once, the real
    `systemd.timer` for vmtest's Thursday cycle needs no further action
    — it's already defined; this step is just letting it fire
    unattended for the first time and watching it.
19. Leave `var.fleet.autoUpdate.enable` off on both hosts for now —
    it has no use until a headless server exists. Keep using
    `fleet-pull-update` manually on `alaptop`.
20. Let it run a few weekly cycles before fully trusting it — watch
    Discord for the Thursday heartbeat and per-host cache-warm messages
    each week.
