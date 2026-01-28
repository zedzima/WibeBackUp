#!/bin/bash
# VibeBackUp — Auto-save clean conversation before compaction
# Called by PreCompact hook
# Extracts only user questions and assistant text responses (no tool calls, no thinking)

set -euo pipefail

PROJECT_DIR="${PWD}"
TIMESTAMP=$(date "+%Y-%m-%d %H:%M")
CLAUDE_PROJECTS_DIR="$HOME/.claude/projects"

# Ensure sessions directory exists
mkdir -p "${PROJECT_DIR}/.claude/sessions"

# Find next session number
LAST_SESSION=$(ls -1 "${PROJECT_DIR}/.claude/sessions/conversation-"*.md 2>/dev/null | sort -V | tail -1 || true)

if [ -z "$LAST_SESSION" ]; then
    NEXT_NUM="001"
else
    LAST_NUM=$(basename "$LAST_SESSION" | sed 's/conversation-\([0-9]*\)\.md/\1/')
    NEXT_NUM=$(printf "%03d" $((10#$LAST_NUM + 1)))
fi

SESSION_FILE="${PROJECT_DIR}/.claude/sessions/conversation-${NEXT_NUM}.md"

# Find the most recent transcript
# Claude stores transcripts in ~/.claude/projects/{encoded-path}/{uuid}.jsonl
TRANSCRIPT_PATH=""

# Try to find the most recent .jsonl file across all project folders
if [ -d "$CLAUDE_PROJECTS_DIR" ]; then
    TRANSCRIPT_PATH=$(find "$CLAUDE_PROJECTS_DIR" -name "*.jsonl" -type f -exec stat -f '%m %N' {} \; 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
fi

# Check if we found a transcript
if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
    cat > "$SESSION_FILE" << EOF
# Session — ${TIMESTAMP} (auto-saved before compact)

## Status
Transcript not found. Manual /save-session recommended.

## Searched
- $CLAUDE_PROJECTS_DIR

---
*Auto-saved by VibeBackUp PreCompact hook*
EOF
    echo "VibeBackUp: No transcript found, created marker at ${SESSION_FILE}"
    exit 0
fi

# Extract clean conversation from JSONL transcript
# - User messages: type="user", userType="external", extract .message (string)
# - Assistant text: type="assistant", extract .message.content[] where type="text"
# - Skip: tool_result messages, thinking, tool_use

{
    echo "# Session Conversation — ${TIMESTAMP}"
    echo ""
    echo "## Messages"
    echo ""

    # Process each line of JSONL
    while IFS= read -r line; do
        msg_type=$(echo "$line" | jq -r '.type // empty' 2>/dev/null)
        user_type=$(echo "$line" | jq -r '.userType // empty' 2>/dev/null)

        if [ "$msg_type" = "user" ] && [ "$user_type" = "external" ]; then
            # External user message - this is actual user input
            # .message can be a string (simple message) or object with content array (tool results - skip those)
            msg_content=$(echo "$line" | jq -r '
                if (.message | type) == "string" then
                    .message
                elif (.message.content | type) == "string" then
                    .message.content
                elif (.message.content | type) == "array" then
                    # Check if it contains tool_result - skip if so
                    if (.message.content[0].type // "") == "tool_result" then
                        ""
                    else
                        .message.content | map(select(type == "string") // .text // "") | join("\n")
                    end
                else
                    ""
                end
            ' 2>/dev/null)

            if [ -n "$msg_content" ] && [ "$msg_content" != "null" ]; then
                echo "**User:**"
                echo "$msg_content"
                echo ""
                echo "---"
                echo ""
            fi
        elif [ "$msg_type" = "assistant" ]; then
            # Assistant message - extract only text content (skip thinking, tool_use)
            text_content=$(echo "$line" | jq -r '
                if .message.content then
                    [.message.content[] | select(.type == "text") | .text] | join("\n\n")
                else
                    ""
                end
            ' 2>/dev/null)

            if [ -n "$text_content" ]; then
                echo "**Assistant:**"
                echo "$text_content"
                echo ""
                echo "---"
                echo ""
            fi
        fi
    done < "$TRANSCRIPT_PATH"

    echo ""
    echo "---"
    echo "*Auto-saved by VibeBackUp PreCompact hook*"
    echo "*Source: $(basename "$TRANSCRIPT_PATH")*"

} > "$SESSION_FILE"

# Check if file has actual content (more than just headers)
LINE_COUNT=$(wc -l < "$SESSION_FILE" | tr -d ' ')
if [ "$LINE_COUNT" -lt 15 ]; then
    echo "VibeBackUp: Warning - conversation file seems empty, transcript may have different format"
fi

# Rotate old sessions (keep max 5) - macOS compatible
cd "${PROJECT_DIR}/.claude/sessions" 2>/dev/null || exit 0
TOTAL=$(ls -1 conversation-*.md 2>/dev/null | wc -l | tr -d ' ')
if [ "$TOTAL" -gt 5 ]; then
    TO_DELETE=$((TOTAL - 5))
    ls -1 conversation-*.md 2>/dev/null | sort -V | head -n "$TO_DELETE" | xargs rm -f 2>/dev/null || true
fi

echo "VibeBackUp: Saved conversation to ${SESSION_FILE}"
echo "VibeBackUp: Extracted from $(basename "$TRANSCRIPT_PATH")"
