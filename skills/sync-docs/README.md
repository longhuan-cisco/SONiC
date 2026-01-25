# Sync Docs Skill

A generic, extensible script for syncing documentation files from multiple source repositories to a target repository.

## Features

- **Multi-source support**: Sync from multiple repositories with different branch patterns
- **Branch pattern matching**: Use glob patterns like `claude/*` to match multiple branches
- **Recursive search**: Finds all `.md` files recursively in source directories
- **Conflict resolution**: Automatically selects the file with the latest modification date when the same filename appears in multiple branches
- **Flattened output**: Copies files to target directory's first layer (regardless of source subfolder structure)
- **Detailed commit messages**: Generates commit messages with:
  - Source branch name
  - Original file path
  - SHA-based URL links to exact source snapshots
  - Conflict information showing all branches that contained the file

## Files

- `sync-docs.sh` - Main sync script
- `sync-docs-config.sh` - Configuration file (sources, targets, branch patterns)
- `README.md` - This documentation

## Usage

### Basic Usage

```bash
# Run with default configuration
./sync-docs.sh

# Run with custom configuration file
./sync-docs.sh /path/to/my-config.sh

# Dry run (preview without copying files)
DRY_RUN=true ./sync-docs.sh

# Keep work directory for debugging
KEEP_WORK_DIR=true ./sync-docs.sh
```

### Configuration

Edit `sync-docs-config.sh` to customize:

#### Target Settings

```bash
# Target repository information
TARGET_REPO="longhuan-cisco/SONiC"
TARGET_REPO_URL="https://github.com/longhuan-cisco/SONiC.git"
TARGET_REPO_PATH="/path/to/local/SONiC"  # Local clone path
TARGET_DIR="docs"                         # Target directory
TARGET_BRANCH="main"                      # Target branch
```

#### Source Repositories

Add source repositories to the `SOURCE_REPOS` array:

```bash
SOURCE_REPOS=(
    # Format: "repo_name|repo_url|source_dir|branch_patterns"

    # Example 1: Sync from specific branches
    "sonic-swss|https://github.com/longhuan-cisco/sonic-swss.git|docs|claude/*,swss_docs"

    # Example 2: Sync from master branch only
    "sonic-sairedis|https://github.com/sonic-net/sonic-sairedis.git|doc|master"

    # Example 3: Sync from multiple pattern branches
    "my-repo|https://github.com/org/repo.git|documentation|feature/*,release/*,main"
)
```

#### Branch Pattern Examples

| Pattern | Matches |
|---------|---------|
| `main` | Only the `main` branch |
| `claude/*` | All branches starting with `claude/` |
| `feature/*` | All branches starting with `feature/` |
| `v1.*` | Branches like `v1.0`, `v1.1`, `v1.2-beta` |
| `*-docs` | Branches ending with `-docs` |

## Workflow Example

1. **Configure sources and target** in `sync-docs-config.sh`

2. **Run the script**:
   ```bash
   cd /path/to/SONiC
   ./skills/sync-docs/sync-docs.sh
   ```

3. **Review the output** - the script shows:
   - Which files were found
   - Conflict resolutions (which version was selected)
   - Generated commit message

4. **Commit and push**:
   ```bash
   git add docs/
   git commit -F /tmp/sync-docs-*/commit_message.txt
   git push
   ```

## Adding a New Source Repository

1. Open `sync-docs-config.sh`

2. Add a new entry to `SOURCE_REPOS`:
   ```bash
   SOURCE_REPOS=(
       # Existing sources...
       "sonic-swss|https://github.com/longhuan-cisco/sonic-swss.git|docs|claude/*,swss_docs"

       # New source
       "new-repo|https://github.com/org/new-repo.git|docs|main,develop"
   )
   ```

3. Run the sync script

## Conflict Resolution

When the same filename exists in multiple branches:

1. The script compares modification timestamps (git commit dates)
2. The version with the **latest modification date** is selected
3. The commit message includes "Also in:" notes showing other branches that had the file

Example commit message for a conflicted file:
```
8. port-oper-status-flow.md
   - Source branch: swss_docs (latest: 2026-01-19 06:00:40 UTC)
   - Original path: docs/port-oper-status-flow.md
   - Source URL: https://github.com/longhuan-cisco/sonic-swss/blob/b9e18d0.../docs/port-oper-status-flow.md
   - Also in: claude/review-oper-status-docs-9rOg5 (older: 2026-01-19 01:34:15 UTC)
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DRY_RUN` | `false` | Set to `true` for preview mode |
| `KEEP_WORK_DIR` | `false` | Set to `true` to preserve temp directory |
| `WORK_DIR` | `/tmp/sync-docs-$$` | Custom work directory path |
| `TARGET_REPO_PATH` | `$(pwd)` | Override target repo local path |

## Troubleshooting

### No branches found matching patterns
- Check that the branch patterns in config match actual remote branches
- Run `git branch -r` in the source repo to see available branches

### Permission denied
- Make the script executable: `chmod +x sync-docs.sh`

### Files not found in source
- Verify the `source_dir` path exists in the source repository
- Check if the branch has the docs directory

## Current Default Configuration

**Target:**
- Repository: `longhuan-cisco/SONiC`
- Directory: `docs/`
- Branch: `claude/sync-sonic-docs-bIB0B`

**Source:**
- Repository: `longhuan-cisco/sonic-swss`
- Directory: `docs/`
- Branch patterns: `claude/*`, `swss_docs`
