#!/bin/bash
#
# sync-docs-config.sh - Configuration for sync-docs.sh
#
# This file defines source repositories, branch patterns, and target settings.
# Modify this file to add new sources or change the target.
#

# ==============================================================================
# TARGET CONFIGURATION
# ==============================================================================

# Target repository name (for display purposes)
TARGET_REPO="longhuan-cisco/SONiC"

# Target repository URL (for cloning if needed)
TARGET_REPO_URL="https://github.com/longhuan-cisco/SONiC.git"

# Local path to target repository (where files will be copied)
# This should be set to the actual path of the cloned target repo
TARGET_REPO_PATH="${TARGET_REPO_PATH:-$(pwd)}"

# Target directory within the repository (relative path)
TARGET_DIR="docs"

# Target branch for commits
TARGET_BRANCH="claude/sync-sonic-docs-bIB0B"

# ==============================================================================
# SOURCE REPOSITORIES CONFIGURATION
# ==============================================================================
#
# Format: "repo_name|repo_url|source_dir|branch_pattern1,branch_pattern2,..."
#
# - repo_name: A unique identifier for the repository
# - repo_url: Git clone URL
# - source_dir: Directory to search for md files (e.g., "docs")
# - branch_patterns: Comma-separated list of branch patterns (supports glob *)
#
# Examples:
#   "sonic-swss|https://github.com/longhuan-cisco/sonic-swss.git|docs|claude/*,swss_docs"
#   "sonic-sairedis|https://github.com/sonic-net/sonic-sairedis.git|doc|master"
#
# ==============================================================================

SOURCE_REPOS=(
    # sonic-swss repository - SWSS documentation
    "sonic-swss|https://github.com/longhuan-cisco/sonic-swss.git|docs|claude/*,swss_docs"

    # Add more source repositories below:
    # "repo-name|https://github.com/org/repo.git|docs|branch1,branch2,pattern/*"
)

# ==============================================================================
# OPTIONAL SETTINGS
# ==============================================================================

# Set to "true" to keep the work directory after script completes (for debugging)
# KEEP_WORK_DIR="false"

# Set to "true" to perform a dry run (no files copied)
# DRY_RUN="false"

# Custom work directory (default: /tmp/sync-docs-$$)
# WORK_DIR="/tmp/my-sync-work"
