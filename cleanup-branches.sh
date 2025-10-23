#!/bin/bash

# Branch cleanup script
# Deletes merged local and remote branches

set -e  # Exit on error

echo "=========================================="
echo "Branch Cleanup Script"
echo "=========================================="
echo ""

# Ensure we're on master
CURRENT_BRANCH=$(git branch --show-current)
if [ "$CURRENT_BRANCH" != "master" ]; then
    echo "Switching to master branch..."
    git checkout master
fi

echo "Current branch: $(git branch --show-current)"
echo ""

# Delete local branches
echo "Deleting local branches..."
echo "  - revised-ui"
git branch -d revised-ui || git branch -D revised-ui
echo "  - legal"
git branch -d legal || git branch -D legal
echo "✓ Local branches deleted"
echo ""

# Delete remote branches
echo "Deleting remote branches..."
echo "  - origin/claude/additional-features-011CUPPYAnq1djgqJ6UsreWV"
git push origin --delete claude/additional-features-011CUPPYAnq1djgqJ6UsreWV

echo "  - origin/claude/frigate-auth-011CUPPYAnq1djgqJ6UsreWV"
git push origin --delete claude/frigate-auth-011CUPPYAnq1djgqJ6UsreWV

echo "  - origin/claude/frigate-import-enhancements-011CUPPYAnq1djgqJ6UsreWV"
git push origin --delete claude/frigate-import-enhancements-011CUPPYAnq1djgqJ6UsreWV

echo "  - origin/claude/project-overview-011CUPPYAnq1djgqJ6UsreWV"
git push origin --delete claude/project-overview-011CUPPYAnq1djgqJ6UsreWV

echo "✓ Remote branches deleted"
echo ""

# Prune remote references
echo "Pruning stale remote references..."
git fetch --prune
echo "✓ Remote references pruned"
echo ""

echo "=========================================="
echo "Cleanup complete!"
echo "=========================================="
echo ""
echo "Remaining local branches:"
git branch
echo ""
echo "Remaining remote branches:"
git branch -r | grep -E "(claude|release)" || echo "  (no claude/* branches remaining)"
