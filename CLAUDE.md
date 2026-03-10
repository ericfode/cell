# Cell Language Repository

## Beads Configuration

**CRITICAL**: Before running any `bd` command, export the beads directory:

```bash
export BEADS_DIR=/home/nixos/wasteland/cell/.beads
```

This ensures bd connects to the `ce` database, not the town-level `hq` database.
Polecat worktrees inherit the wrong beads path without this.
