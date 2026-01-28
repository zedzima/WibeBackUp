# VibeBackUp

Auto-save conversation history before Claude Code context compaction.

## Problem

When Claude's context window fills up, auto-compact summarizes and loses detailed conversation history. After long breaks, there's no way to see what was discussed.

## Solution

VibeBackUp automatically extracts and saves **clean conversation logs** (user questions + assistant responses only) before compaction happens. No tool calls, no thinking blocks, no JSON noise — just readable dialogue.

## What's Included

| Component | Purpose |
|-----------|---------|
| `scripts/auto-save-session.sh` | Auto-backup script (called by PreCompact hook) |
| `skills/save-session/` | Manual session save with structured summary |
| `skills/load-session/` | Restore context from previous session |
| `skills/init-project/` | Initialize project structure |

## Installation

### 1. Copy skills to Claude

```bash
cp -r skills/* ~/.claude/skills/
```

### 2. Copy auto-save script

```bash
mkdir -p ~/.claude/scripts
cp scripts/auto-save-session.sh ~/.claude/scripts/
chmod +x ~/.claude/scripts/auto-save-session.sh
```

### 3. Configure PreCompact hook

Add to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PreCompact": [
      {
        "matcher": "auto",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/scripts/auto-save-session.sh"
          }
        ]
      }
    ]
  }
}
```

If you already have `settings.json`, merge the `PreCompact` section into your existing `hooks`.

### 4. Restart Claude Code

Skills and hooks are loaded on startup.

## Usage

### Automatic (PreCompact)

When context fills up:
1. PreCompact hook triggers
2. `auto-save-session.sh` finds the current transcript
3. Extracts user messages and assistant text responses
4. Saves to `{project}/.claude/sessions/conversation-XXX.md`

### Manual Skills

```bash
/init-project          # Initialize .claude/ structure in current project
/save-session          # Save structured session summary (tasks, decisions, next steps)
/load-session          # Load previous session context
```

## Output Format

Auto-saved conversations look like this:

```markdown
# Session Conversation — 2026-01-28 14:00

## Messages

**User:**
How do I implement authentication?

---

**Assistant:**
Here's how to implement JWT authentication...

---

*Auto-saved by VibeBackUp PreCompact hook*
```

## What's Extracted

| Included | Excluded |
|----------|----------|
| User questions | Tool calls |
| Assistant visible responses | Tool results (file contents, outputs) |
| | Thinking/reasoning blocks |
| | System messages |

## Project Structure After Init

```
your-project/
└── .claude/
    ├── SESSION.md              # Current session state
    ├── PLAN.md                 # Project plan
    └── sessions/
        ├── session-001.md      # Manual save (structured)
        ├── conversation-001.md # Auto-save (dialogue)
        └── ...
```

## How It Works

1. Claude Code transcripts are stored in `~/.claude/projects/{encoded-path}/*.jsonl`
2. The script finds the most recent transcript
3. Parses JSONL and filters:
   - `type: "user"` + `userType: "external"` → user messages
   - `type: "assistant"` → `content[].type == "text"` → visible responses
4. Formats as readable markdown
5. Saves to current project's `.claude/sessions/`
6. Rotates old files (keeps last 5)

## Gitignore

Add to your project's `.gitignore`:

```
.claude/sessions/
```

Sessions contain conversation history — usually shouldn't be committed.

## Testing

Run manually to verify:

```bash
cd your-project
~/.claude/scripts/auto-save-session.sh
cat .claude/sessions/conversation-001.md
```

## Requirements

- Claude Code CLI
- `jq` (for JSON parsing)
- macOS or Linux

## License

MIT

## Contributing

Issues and PRs welcome at https://github.com/anthropics/claude-code/issues
