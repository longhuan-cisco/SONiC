#!/bin/bash
#
# sync-docs.sh - Sync documentation files from source repositories to target repository
#
# This script:
# 1. Clones source repositories
# 2. Scans specified branches (supports glob patterns)
# 3. Recursively finds markdown files in source directories
# 4. Compares with existing files and only copies if changed
# 5. Handles conflicts by choosing the file with latest modification date
# 6. Generates detailed commit messages with SHA-based source URLs
#
# Usage: ./sync-docs.sh [config_file]
#        Default config: ./sync-docs-config.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${1:-$SCRIPT_DIR/sync-docs-config.sh}"
WORK_DIR="${WORK_DIR:-/tmp/sync-docs-$$}"
DRY_RUN="${DRY_RUN:-false}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Load configuration
if [[ ! -f "$CONFIG_FILE" ]]; then
    log_error "Configuration file not found: $CONFIG_FILE"
    exit 1
fi

source "$CONFIG_FILE"

# Validate required configuration
validate_config() {
    local required_vars=("TARGET_REPO" "TARGET_REPO_URL" "TARGET_DIR" "TARGET_BRANCH")
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            log_error "Required configuration variable not set: $var"
            exit 1
        fi
    done

    if [[ ${#SOURCE_REPOS[@]} -eq 0 ]]; then
        log_error "No source repositories configured (SOURCE_REPOS array is empty)"
        exit 1
    fi
}

# Clone a repository
clone_repo() {
    local repo_url="$1"
    local repo_name="$2"
    local clone_dir="$WORK_DIR/$repo_name"

    if [[ -d "$clone_dir" ]]; then
        log_info "Repository already cloned: $repo_name"
        return 0
    fi

    log_info "Cloning repository: $repo_url"
    git clone "$repo_url" "$clone_dir" 2>/dev/null
    cd "$clone_dir" && git fetch --all 2>/dev/null
}

# Get branches matching patterns
get_matching_branches() {
    local repo_dir="$1"
    shift
    local patterns=("$@")

    cd "$repo_dir"
    local all_branches=$(git branch -r | sed 's/origin\///' | tr -d ' ')

    for branch in $all_branches; do
        for pattern in "${patterns[@]}"; do
            # Handle glob patterns
            if [[ "$branch" == $pattern ]]; then
                echo "$branch"
                break
            fi
        done
    done | sort -u
}

# Get all md files recursively in a directory on a branch
get_md_files() {
    local repo_dir="$1"
    local branch="$2"
    local source_dir="$3"

    cd "$repo_dir"
    git ls-tree -r --name-only "origin/$branch" "$source_dir/" 2>/dev/null | grep '\.md$' || true
}

# Get the last modification date and commit SHA for a file
get_file_info() {
    local repo_dir="$1"
    local branch="$2"
    local file_path="$3"

    cd "$repo_dir"
    # Returns: timestamp SHA
    git log -1 --format="%ct %H" "origin/$branch" -- "$file_path" 2>/dev/null
}

# Check if source file content differs from target file
file_needs_update() {
    local repo_dir="$1"
    local branch="$2"
    local source_path="$3"
    local target_path="$4"

    # If target doesn't exist, it needs update
    if [[ ! -f "$target_path" ]]; then
        return 0  # true, needs update
    fi

    # Compare content
    cd "$repo_dir"
    local source_content=$(git show "origin/$branch:$source_path" 2>/dev/null)
    local target_content=$(cat "$target_path" 2>/dev/null)

    if [[ "$source_content" != "$target_content" ]]; then
        return 0  # true, needs update
    fi

    return 1  # false, no update needed
}

# Main sync function
sync_docs() {
    validate_config

    mkdir -p "$WORK_DIR"
    log_info "Working directory: $WORK_DIR"

    # Associative arrays to track files and their metadata
    declare -A file_timestamps    # filename -> timestamp
    declare -A file_sources       # filename -> "repo|branch|path|sha"
    declare -A file_conflicts     # filename -> "branch1:timestamp1,branch2:timestamp2,..."

    # Process each source repository
    for repo_config in "${SOURCE_REPOS[@]}"; do
        IFS='|' read -r repo_name repo_url source_dir branch_patterns_str <<< "$repo_config"
        IFS=',' read -ra branch_patterns <<< "$branch_patterns_str"

        log_info "Processing repository: $repo_name"
        log_info "  Source directory: $source_dir"
        log_info "  Branch patterns: ${branch_patterns[*]}"

        # Clone repository
        clone_repo "$repo_url" "$repo_name"
        local repo_dir="$WORK_DIR/$repo_name"

        # Get matching branches
        local branches=$(get_matching_branches "$repo_dir" "${branch_patterns[@]}")

        if [[ -z "$branches" ]]; then
            log_warn "  No branches found matching patterns"
            continue
        fi

        log_info "  Found branches: $(echo $branches | tr '\n' ' ')"

        # Process each branch
        for branch in $branches; do
            log_info "  Scanning branch: $branch"

            # Get md files
            local md_files=$(get_md_files "$repo_dir" "$branch" "$source_dir")

            if [[ -z "$md_files" ]]; then
                log_info "    No md files found in $source_dir/"
                continue
            fi

            # Process each file
            while IFS= read -r file_path; do
                local filename=$(basename "$file_path")
                local file_info=$(get_file_info "$repo_dir" "$branch" "$file_path")
                local timestamp=$(echo "$file_info" | cut -d' ' -f1)
                local sha=$(echo "$file_info" | cut -d' ' -f2)

                if [[ -z "$timestamp" ]]; then
                    log_warn "    Could not get timestamp for: $file_path"
                    continue
                fi

                # Track conflicts
                if [[ -n "${file_sources[$filename]}" ]]; then
                    local existing_ts="${file_timestamps[$filename]}"
                    if [[ -z "${file_conflicts[$filename]}" ]]; then
                        # First conflict - add existing source
                        IFS='|' read -r ex_repo ex_branch ex_path ex_sha <<< "${file_sources[$filename]}"
                        file_conflicts[$filename]="$ex_branch:$existing_ts"
                    fi
                    file_conflicts[$filename]="${file_conflicts[$filename]},$branch:$timestamp"

                    # Only update if newer
                    if [[ "$timestamp" -gt "$existing_ts" ]]; then
                        log_info "    Found newer version of $filename in $branch"
                        file_timestamps[$filename]="$timestamp"
                        file_sources[$filename]="$repo_name|$branch|$file_path|$sha"
                    fi
                else
                    log_info "    Found: $filename"
                    file_timestamps[$filename]="$timestamp"
                    file_sources[$filename]="$repo_name|$branch|$file_path|$sha"
                fi
            done <<< "$md_files"
        done
    done

    # Check if any files were found
    if [[ ${#file_sources[@]} -eq 0 ]]; then
        log_warn "No markdown files found to sync"
        exit 0
    fi

    log_info "Total files found in sources: ${#file_sources[@]}"

    # Prepare target directory
    local target_full_path="$TARGET_REPO_PATH/$TARGET_DIR"
    mkdir -p "$target_full_path"

    # Track changes
    declare -a new_files=()
    declare -a updated_files=()
    declare -a unchanged_files=()
    declare -A changed_file_sources  # Only files that changed

    # Check each file for changes
    for filename in $(echo "${!file_sources[@]}" | tr ' ' '\n' | sort); do
        IFS='|' read -r repo_name branch file_path sha <<< "${file_sources[$filename]}"
        local repo_dir="$WORK_DIR/$repo_name"
        local target_file="$target_full_path/$filename"

        if [[ ! -f "$target_file" ]]; then
            new_files+=("$filename")
            changed_file_sources[$filename]="${file_sources[$filename]}"
        elif file_needs_update "$repo_dir" "$branch" "$file_path" "$target_file"; then
            updated_files+=("$filename")
            changed_file_sources[$filename]="${file_sources[$filename]}"
        else
            unchanged_files+=("$filename")
        fi
    done

    # Report status
    echo ""
    log_info "=== Sync Status ==="
    log_info "New files:       ${#new_files[@]}"
    log_info "Updated files:   ${#updated_files[@]}"
    log_info "Unchanged files: ${#unchanged_files[@]}"

    # Check if any changes needed
    local total_changes=$((${#new_files[@]} + ${#updated_files[@]}))

    if [[ $total_changes -eq 0 ]]; then
        log_success "All files are up to date. No changes needed."
        echo ""
        echo "=== Unchanged Files ==="
        for f in "${unchanged_files[@]}"; do
            echo "  ✓ $f"
        done
        exit 0
    fi

    # Show what will be changed
    if [[ ${#new_files[@]} -gt 0 ]]; then
        echo ""
        echo "=== New Files ==="
        for f in "${new_files[@]}"; do
            echo "  + $f"
        done
    fi

    if [[ ${#updated_files[@]} -gt 0 ]]; then
        echo ""
        echo "=== Updated Files ==="
        for f in "${updated_files[@]}"; do
            echo "  ~ $f"
        done
    fi

    if [[ ${#unchanged_files[@]} -gt 0 ]]; then
        echo ""
        echo "=== Unchanged Files (skipped) ==="
        for f in "${unchanged_files[@]}"; do
            echo "  ✓ $f"
        done
    fi

    # Copy changed files and build commit message
    local commit_body="Sync documentation files from source repositories to $TARGET_DIR/.
For files appearing in multiple branches, the version with the latest
modification date was selected.

"

    if [[ ${#new_files[@]} -gt 0 ]]; then
        commit_body+="New files added: ${#new_files[@]}
"
    fi

    if [[ ${#updated_files[@]} -gt 0 ]]; then
        commit_body+="Files updated: ${#updated_files[@]}
"
    fi

    commit_body+="
Source details for each synced file:
"
    local file_num=1

    for filename in $(echo "${!changed_file_sources[@]}" | tr ' ' '\n' | sort); do
        IFS='|' read -r repo_name branch file_path sha <<< "${changed_file_sources[$filename]}"
        local repo_dir="$WORK_DIR/$repo_name"

        # Get the repo URL for commit message (extract from SOURCE_REPOS)
        local github_url=""
        for repo_config in "${SOURCE_REPOS[@]}"; do
            IFS='|' read -r r_name r_url r_dir r_patterns <<< "$repo_config"
            if [[ "$r_name" == "$repo_name" ]]; then
                # Convert git URL to GitHub web URL
                github_url=$(echo "$r_url" | sed 's|git@github.com:|https://github.com/|' | sed 's|\.git$||')
                break
            fi
        done

        # Determine if new or updated
        local change_type="updated"
        for nf in "${new_files[@]}"; do
            if [[ "$nf" == "$filename" ]]; then
                change_type="new"
                break
            fi
        done

        # Copy file
        if [[ "$DRY_RUN" != "true" ]]; then
            cd "$repo_dir"
            git show "origin/$branch:$file_path" > "$target_full_path/$filename"
        fi

        # Build commit message entry
        commit_body+="
$file_num. $filename [$change_type]
   - Source branch: $branch"

        # Add conflict info if applicable
        if [[ -n "${file_conflicts[$filename]}" ]]; then
            local ts="${file_timestamps[$filename]}"
            local date_str=$(date -d "@$ts" -u '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null || date -r "$ts" -u '+%Y-%m-%d %H:%M:%S UTC')
            commit_body+=" (latest: $date_str)"
        fi

        commit_body+="
   - Original path: $file_path
   - Source URL: $github_url/blob/$sha/$file_path"

        # Add "Also in" info for conflicts
        if [[ -n "${file_conflicts[$filename]}" ]]; then
            IFS=',' read -ra conflict_entries <<< "${file_conflicts[$filename]}"
            for entry in "${conflict_entries[@]}"; do
                IFS=':' read -r c_branch c_ts <<< "$entry"
                if [[ "$c_branch" != "$branch" ]]; then
                    local c_date=$(date -d "@$c_ts" -u '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null || date -r "$c_ts" -u '+%Y-%m-%d %H:%M:%S UTC')
                    commit_body+="
   - Also in: $c_branch (older: $c_date)"
                fi
            done
        fi

        ((file_num++))
    done

    # Save commit message to file
    local commit_msg_file="$WORK_DIR/commit_message.txt"
    echo "Sync documentation from source repositories

$commit_body" > "$commit_msg_file"

    echo ""
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "DRY RUN - no files were actually copied"
        echo ""
        echo "=== Commit Message Preview ==="
        cat "$commit_msg_file"
    else
        log_success "Files synced to: $target_full_path"
        log_info "Commit message saved to: $commit_msg_file"
        echo ""
        echo "=== Commit Message ==="
        cat "$commit_msg_file"
    fi

    # Return the commit message file path for use by caller
    echo ""
    echo "COMMIT_MSG_FILE=$commit_msg_file"
}

# Cleanup function
cleanup() {
    if [[ -d "$WORK_DIR" && "$KEEP_WORK_DIR" != "true" ]]; then
        log_info "Cleaning up work directory: $WORK_DIR"
        rm -rf "$WORK_DIR"
    fi
}

# Run main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    trap cleanup EXIT
    sync_docs
fi
