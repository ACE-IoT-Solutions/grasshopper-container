#!/bin/bash
# Verify that dependencies are properly cloned and ready for build

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DEPS_DIR="$PROJECT_ROOT/deps"

echo "==========================================="
echo "Dependency Verification"
echo "==========================================="
echo ""

ERRORS=0

# Check if deps directory exists
if [ ! -d "$DEPS_DIR" ]; then
    echo "❌ ERROR: deps/ directory not found"
    echo ""
    echo "Run this first:"
    echo "  ./scripts/update-deps.sh"
    exit 1
fi

echo "✓ deps/ directory exists"

# Required paths for build
REQUIRED_PATHS=(
    "volttron"
    "grasshopper/Grasshopper"
)

echo ""
echo "Checking required paths..."
echo ""

for path in "${REQUIRED_PATHS[@]}"; do
    full_path="$DEPS_DIR/$path"
    if [ -d "$full_path" ]; then
        echo "  ✓ $path"
    else
        echo "  ❌ MISSING: $path"
        ERRORS=$((ERRORS + 1))
    fi
done

echo ""

if [ $ERRORS -eq 0 ]; then
    echo "==========================================="
    echo "✓ All dependencies verified!"
    echo "==========================================="
    echo ""
    echo "Ready to build:"
    echo "  docker build -t grasshopper ."
    echo ""
    exit 0
else
    echo "==========================================="
    echo "❌ $ERRORS missing dependencies"
    echo "==========================================="
    echo ""
    echo "Fix by running:"
    echo "  ./scripts/update-deps.sh"
    echo ""
    exit 1
fi
