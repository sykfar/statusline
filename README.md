# @grwthlab/statusline

grwthlab-branded statusline for [Claude Code](https://claude.ai/code) with project detection, extended git info, and system status.

```
◆ grwth/rbac │ Opus 4 │ ✍️ 34% │ main +3 ↑2↓0 │ ⏱ 12m │ ◑ default
⎔ node 22.4 │ pnpm │ ● :3000 │ "fix: auth token refresh"

current ●●●●○○○○○○  42% ⟳ 3:15pm  ⏳ 2h 14m
weekly  ●●○○○○○○○○  18% ⟳ apr 10
```

## Features

**Line 1 — Status**
- Purple diamond brand marker with project detection
- Model name and context window usage (color-coded)
- Git branch, uncommitted changes count, ahead/behind remote
- Session duration and effort level

**Line 2 — System**
- Node.js version (cached)
- Package manager (detected from lockfile)
- Running dev servers (common ports)
- Last commit message

**Lines 3+ — Rate Limits**
- 5-hour rolling limit with visual progress bar, reset time, and time remaining (⏳)
- 7-day rolling limit
- Extra credits (if enabled)

## Project Detection

Automatically recognizes grwthlab projects:
- `package.json` name matching `@grwthlab/*` or `grwth*`
- Directory names like `grwth.rbac` displayed as `grwth/rbac`
- Falls back to plain directory name for non-grwth projects

## Install

Requires `jq`, `curl`, and `git`.

```bash
# macOS
brew install jq

# Install
npx @grwthlab/statusline

# Uninstall
npx @grwthlab/statusline --uninstall
```

## Customization

Colors are configurable via `~/.claude/statusline.config.json` (created automatically on install):

```json
{
  "colors": {
    "accent": "#8B5CF6",
    "success": "#22C55E",
    "warning": "#F59E0B",
    "caution": "#EAB308",
    "error": "#E05252",
    "muted": "#9CA3AF",
    "text": "#DCDCDC",
    "info": "#56B6C2"
  }
}
```

All keys are optional — missing values fall back to the defaults above. Edit the file and restart Claude Code to apply changes.

| Key       | Default | Usage                              |
|-----------|---------|------------------------------------|
| `accent`  | #8B5CF6 | Brand marker, effort high          |
| `success` | #22C55E | 0-49% usage, running servers       |
| `warning` | #F59E0B | 50-69% usage                       |
| `caution` | #EAB308 | 70-89% usage                       |
| `error`   | #E05252 | 90-100% usage, change count        |
| `muted`   | #9CA3AF | Separators, dimmed text            |
| `text`    | #DCDCDC | Model name, labels, reset times    |
| `info`    | #56B6C2 | Git branch name                    |

## License

MIT
