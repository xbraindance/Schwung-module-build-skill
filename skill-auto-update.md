# Schwung Skill Auto-Update via Claude Code Hooks

This document explains how the Schwung Module Creator skill auto-updates itself using Claude Code hooks.

## Architecture

```
User invokes skill
    ↓
Claude Code reads settings.json hooks
    ↓
Hook triggers BEFORE skill execution
    ↓
skill-update.sh runs
    ↓
Checks GitHub for updates
    ↓
If newer version exists:
  - Downloads from GitHub
  - Compares with local version
  - Backs up current version
  - Updates local SKILL.md
    ↓
Skill execution continues (with latest code)
```

## How It Works

### 1. Update Script (skill-update.sh)

Located at `scripts/skill-update.sh`, this script:
- **Checks GitHub** for the latest skill.md
- **Downloads** the remote version via curl
- **Compares** local vs remote using SHA256 hashes
- **Backs up** the current version before updating
- **Throttles** checks (only checks every hour max)
- **Handles errors gracefully** (continues if check fails)

### 2. Claude Code Hook

A hook is a shell command that runs in response to system events. We use the `skill:invoke` event:

```json
{
  "hooks": {
    "skill:invoke": {
      "command": "bash ~/.claude/projects/-Users-click-Desktop-Move/scripts/skill-update.sh"
    }
  }
}
```

When ANY skill is invoked, the hook runs before execution. For efficiency, the script:
- Only updates once per hour
- Silently skips if GitHub is unreachable
- Runs in <100ms normally (just timestamp check)

### 3. Backup & Recovery

If an update breaks something:

```bash
# Restore previous version
cp ~/.claude/skills/schwung-module-creator/SKILL.md.backup \
   ~/.claude/skills/schwung-module-creator/SKILL.md
```

## Setup Instructions

### Step 1: Make the Script Executable

```bash
chmod +x /Users/click/Desktop/Move/schwung/scripts/skill-update.sh
```

### Step 2: Open Claude Code Settings

In Claude Code settings (`.claude/settings.json` or via UI):

### Step 3: Add the Hook Configuration

Add this to your `settings.json` under the `hooks` section:

```json
{
  "hooks": {
    "skill:invoke": {
      "description": "Auto-update Schwung skill from GitHub",
      "command": "bash /Users/click/Desktop/Move/schwung/scripts/skill-update.sh",
      "silent": true
    }
  }
}
```

**Note:** Adjust the path if your project is in a different location. Use absolute paths, not relative paths.

### Step 4: Verify Setup

1. Run the script manually to test:
   ```bash
   bash /Users/click/Desktop/Move/schwung/scripts/skill-update.sh
   ```

2. Check that it created the skill file:
   ```bash
   ls -lh ~/.claude/skills/schwung-module-creator/SKILL.md
   ```

3. Invoke the skill in Claude Code — the hook should run silently in the background

## What Gets Updated

When GitHub has a newer version, the following are automatically updated:

- ✅ All API documentation
- ✅ Module structure and patterns
- ✅ Build/deployment commands
- ✅ Troubleshooting guides
- ✅ Code style guidelines
- ✅ New features and capabilities

The skill picks up the latest changes **on next skill invocation**.

## Throttling & Performance

The script includes smart throttling to avoid excessive GitHub requests:

```bash
CHECK_INTERVAL=3600  # Check every hour max
```

**How it works:**
1. Script checks timestamp in `~/.cache/schwung-skill/last_check.txt`
2. If less than 1 hour has passed since last check, skip the HTTP request
3. Cache is updated on every run (even if no check was performed)
4. First run always checks (no timestamp yet)

**Result:** After the first check, subsequent runs complete in <1ms (just a file stat).

## Manual Update

To force an immediate update without waiting for the hook:

```bash
bash /Users/click/Desktop/Move/schwung/scripts/skill-update.sh
```

To see what changed:

```bash
# View the backup (old version)
diff ~/.claude/skills/schwung-module-creator/SKILL.md.backup \
     ~/.claude/skills/schwung-module-creator/SKILL.md
```

## Troubleshooting

### Hook not running

1. Check settings.json syntax (must be valid JSON)
2. Verify the hook path is correct:
   ```bash
   ls -la /Users/click/Desktop/Move/schwung/scripts/skill-update.sh
   ```
3. Check file is executable:
   ```bash
   test -x /Users/click/Desktop/Move/schwung/scripts/skill-update.sh && echo "OK" || echo "Not executable"
   ```

### GitHub unreachable

If the GitHub URL is down:
- Script silently skips update (continues normally)
- Uses cached version from last successful check
- No user interaction required

### Rollback failed update

If an update causes issues:

```bash
# Restore from backup
cp ~/.claude/skills/schwung-module-creator/SKILL.md.backup \
   ~/.claude/skills/schwung-module-creator/SKILL.md

# Delete the backup to trigger a fresh download next time
rm ~/.claude/skills/schwung-module-creator/SKILL.md.backup
```

### Disable auto-update

Remove or comment out the hook in `settings.json`:

```json
{
  "hooks": {
    // "skill:invoke": { ... }  // Commented out to disable
  }
}
```

## How GitHub URL is Monitored

The skill checks this file for updates:

```
https://raw.githubusercontent.com/xbraindance/Schwung-Module-Creator-skill/main/skill.md
```

**Update sources:**
- `main` branch is the only source (production-ready)
- Updates go to GitHub → Raw GitHub URL → Synced to local skill
- You control the update frequency (default: hourly)

## Advanced: Custom Check Interval

To change the check interval, edit the script:

```bash
# In skill-update.sh, change this line:
CHECK_INTERVAL=3600  # Change to 1800 for 30 minutes, 7200 for 2 hours, etc.
```

Interval is in seconds: `1800` = 30 min, `3600` = 1 hour, `86400` = 1 day

## Summary

| Feature | Benefit |
|---------|---------|
| Automatic | No manual updates needed |
| Throttled | Minimal GitHub requests, fast execution |
| Safe | Backs up before updating |
| Silent | Runs in background, no notifications |
| Reversible | Easy rollback if needed |

Once set up, you get the latest skill features automatically while staying in control.

