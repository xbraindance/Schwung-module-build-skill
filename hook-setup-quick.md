# Quick Setup: Auto-Update Hook (2 minutes)

## TL;DR

1. Copy the hook configuration below
2. Paste into your Claude Code `settings.json`
3. Done! Updates run automatically

## Copy This Config

Add to your `settings.json` in the `hooks` section:

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

## Where to Paste It

**Option A: Via Claude Code UI**
1. Open Claude Code settings (gear icon)
2. Find "Hooks" section
3. Add new hook for `skill:invoke`
4. Paste the command above

**Option B: Direct File Edit**
1. Edit `.claude/settings.json` in your home directory
2. Find (or create) the `"hooks"` object
3. Add the configuration above
4. Save and reload Claude Code

## Example Full settings.json

If you're starting fresh, here's a minimal example:

```json
{
  "version": "1.0",
  "hooks": {
    "skill:invoke": {
      "description": "Auto-update Schwung skill from GitHub",
      "command": "bash /Users/click/Desktop/Move/schwung/scripts/skill-update.sh",
      "silent": true
    }
  }
}
```

## Verify It Works

```bash
# Test the script directly
bash /Users/click/Desktop/Move/schwung/scripts/skill-update.sh

# Check that skill file was created/updated
ls -lh ~/.claude/skills/schwung-module-creator/SKILL.md
```

## What Happens Now

- ✅ Each time you invoke the Schwung skill, it checks GitHub
- ✅ Only checks once per hour (smart throttling)
- ✅ Updates silently if a newer version exists
- ✅ Backs up old version before updating
- ✅ Continues normally even if GitHub is unreachable

## Need More Info?

See `docs/SKILL-AUTO-UPDATE.md` for:
- How it works (architecture)
- Troubleshooting
- Advanced configuration
- Manual update commands

