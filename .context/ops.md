# ops.md — Operations

## systemd (user service suggested)

Template unit: `systemd/discoclaw.service`

Common commands:
```bash
systemctl --user daemon-reload
systemctl --user restart discoclaw.service
systemctl --user status discoclaw.service
journalctl --user -u discoclaw.service -f
```

## Runtime Working Directory
- Default `WORKSPACE_CWD`:
  - `$DISCOCLAW_DATA_DIR/workspace` when `DISCOCLAW_DATA_DIR` is set
  - `./workspace` otherwise
- Optional group CWD: `USE_GROUP_DIR_CWD=1` and `GROUPS_DIR=...`

## Safety
- Prefer running new behavior in a private channel first.
- Keep allowlist strict; do not run with an empty allowlist.
