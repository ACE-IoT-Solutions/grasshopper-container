#!/bin/bash
# Update/clone dependency repositories for Grasshopper Container
# This script reads dependencies.json and clones or updates the repos

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DEPS_FILE="$PROJECT_ROOT/dependencies.json"
DEPS_DIR="$PROJECT_ROOT/deps"

echo "==========================================="
echo "Grasshopper Container - Dependency Manager"
echo "==========================================="
echo ""

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "ERROR: jq is required but not installed."
    echo ""
    echo "Install with:"
    echo "  macOS:   brew install jq"
    echo "  Ubuntu:  sudo apt install jq"
    echo "  RHEL:    sudo dnf install jq"
    exit 1
fi

# Check if dependencies.json exists
if [ ! -f "$DEPS_FILE" ]; then
    echo "ERROR: dependencies.json not found at $DEPS_FILE"
    exit 1
fi

# Create deps directory if it doesn't exist
mkdir -p "$DEPS_DIR"

echo "Dependency file: $DEPS_FILE"
echo "Target directory: $DEPS_DIR"
echo ""

# Read number of dependencies
DEP_COUNT=$(jq '.dependencies | length' "$DEPS_FILE")
echo "Found $DEP_COUNT dependencies to process"
echo ""

# Process each dependency
for i in $(seq 0 $((DEP_COUNT - 1))); do
    NAME=$(jq -r ".dependencies[$i].name" "$DEPS_FILE")
    URL=$(jq -r ".dependencies[$i].url" "$DEPS_FILE")
    BRANCH=$(jq -r ".dependencies[$i].branch" "$DEPS_FILE")
    COMMIT=$(jq -r ".dependencies[$i].commit" "$DEPS_FILE")
    DESCRIPTION=$(jq -r ".dependencies[$i].description" "$DEPS_FILE")

    echo "-------------------------------------------"
    echo "[$((i+1))/$DEP_COUNT] $NAME"
    echo "Description: $DESCRIPTION"
    echo "Repository: $URL"
    echo "Branch: $BRANCH"

    DEP_PATH="$DEPS_DIR/$NAME"

    # Clone or update
    if [ -d "$DEP_PATH/.git" ]; then
        echo "Status: Updating existing repository..."
        cd "$DEP_PATH"

        # Fetch latest changes
        git fetch origin

        # Check if we should update to specific commit or latest
        if [ "$COMMIT" = "latest" ]; then
            echo "Updating to latest $BRANCH..."
            git checkout "$BRANCH"
            git pull origin "$BRANCH"
            CURRENT_COMMIT=$(git rev-parse HEAD)
            echo "Updated to: $CURRENT_COMMIT"
        else
            echo "Checking out specific commit: $COMMIT"
            git checkout "$COMMIT"
            echo "Locked at: $COMMIT"
        fi
    else
        echo "Status: Cloning repository..."
        git clone --branch "$BRANCH" "$URL" "$DEP_PATH"
        cd "$DEP_PATH"

        if [ "$COMMIT" != "latest" ]; then
            echo "Checking out specific commit: $COMMIT"
            git checkout "$COMMIT"
        fi

        CURRENT_COMMIT=$(git rev-parse HEAD)
        echo "Cloned at: $CURRENT_COMMIT"
    fi

    # Verify required paths exist
    REQUIRED_PATHS=$(jq -r ".dependencies[$i].required_paths[]" "$DEPS_FILE" 2>/dev/null || echo "")
    if [ -n "$REQUIRED_PATHS" ]; then
        echo "Verifying required paths..."
        while IFS= read -r req_path; do
            if [ ! -e "$DEP_PATH/$req_path" ]; then
                echo "WARNING: Required path not found: $req_path"
            else
                echo "  ✓ $req_path"
            fi
        done <<< "$REQUIRED_PATHS"
    fi

    echo "✓ Complete"
    echo ""
done

cd "$PROJECT_ROOT"

echo "==========================================="
echo "Dependency Update Complete"
echo "==========================================="
echo ""
echo "Dependencies are located in: $DEPS_DIR"
echo ""
echo "Next steps:"
echo "  1. Review changes: ls -la $DEPS_DIR"
echo "  2. Build container: docker build -t grasshopper ."
echo ""

# Generate lock file with current commit hashes
echo "Generating dependencies.lock.json..."
cat > "$PROJECT_ROOT/dependencies.lock.json" << EOF
{
  "generated": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "note": "This file is auto-generated. Do not edit manually.",
  "locked_versions": [
EOF

for i in $(seq 0 $((DEP_COUNT - 1))); do
    NAME=$(jq -r ".dependencies[$i].name" "$DEPS_FILE")
    URL=$(jq -r ".dependencies[$i].url" "$DEPS_FILE")
    DEP_PATH="$DEPS_DIR/$NAME"

    cd "$DEP_PATH"
    COMMIT_HASH=$(git rev-parse HEAD)
    COMMIT_DATE=$(git log -1 --format=%cd --date=iso)
    COMMIT_MSG=$(git log -1 --format=%s | sed 's/"/\\"/g')
    BRANCH=$(git rev-parse --abbrev-ref HEAD)

    if [ $i -gt 0 ]; then
        echo "," >> "$PROJECT_ROOT/dependencies.lock.json"
    fi

    cat >> "$PROJECT_ROOT/dependencies.lock.json" << EOFENTRY
    {
      "name": "$NAME",
      "url": "$URL",
      "branch": "$BRANCH",
      "commit": "$COMMIT_HASH",
      "commit_date": "$COMMIT_DATE",
      "commit_message": "$COMMIT_MSG"
    }
EOFENTRY
done

cat >> "$PROJECT_ROOT/dependencies.lock.json" << EOF

  ]
}
EOF

echo "✓ Lock file generated: dependencies.lock.json"
echo ""
echo "All dependencies updated successfully!"
