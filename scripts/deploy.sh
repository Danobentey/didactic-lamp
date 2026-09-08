#!/usr/bin/env bash

set -euo pipefail

# ==========================================================
# Fixxir Operations - Apps Script Deployment
# ==========================================================

DEPLOYMENT_ID="AKfycbzWLpKceBMB-N6tpN4_AgaHuufDxF8eHh63-DsxXwAwUg1kDz1U2HrxQyaXtWR0WgLY"

TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"

echo
echo "======================================================"
echo " Fixxir Operations Deployment"
echo "======================================================"
echo

# ==========================================================
# 0. Basic checks
# ==========================================================

if ! command -v git >/dev/null 2>&1; then
  echo "ERROR: git is not installed or not in PATH."
  exit 1
fi

if ! command -v clasp >/dev/null 2>&1; then
  echo "ERROR: clasp is not installed or not in PATH."
  exit 1
fi

if [[ ! -f ".clasp.json" ]]; then
  echo "ERROR: .clasp.json not found."
  echo "Run this script from the Fixxir Apps Script project root."
  exit 1
fi

if [[ -z "$DEPLOYMENT_ID" || "$DEPLOYMENT_ID" == "YOUR_EXISTING_DEPLOYMENT_ID" ]]; then
  echo "ERROR: Set DEPLOYMENT_ID at the top of this script."
  exit 1
fi

# ==========================================================
# 1. Check Git status FIRST
# ==========================================================

echo "------------------------------------------------------"
echo "1. Git working tree status"
echo "------------------------------------------------------"

git status --short

echo
echo "------------------------------------------------------"
echo "2. Git change summary"
echo "------------------------------------------------------"

git diff --stat

# Check tracked + untracked changes.
if [[ -n "$(git status --porcelain)" ]]; then
  HAS_CHANGES=true
else
  HAS_CHANGES=false
fi

# ==========================================================
# 2. Build deployment description
# ==========================================================

if [[ "$HAS_CHANGES" == true ]]; then

  echo
  echo "Local changes detected."
  echo

  read -r -p "What changed in this deployment? " CHANGE_DESCRIPTION

  if [[ -z "$CHANGE_DESCRIPTION" ]]; then
    echo
    echo "ERROR: Deployment description cannot be empty."
    exit 1
  fi

  DESCRIPTION="${CHANGE_DESCRIPTION} - ${TIMESTAMP}"
  COMMIT_MESSAGE="Deploy: ${DESCRIPTION}"

else

  echo
  echo "No local Git changes detected."
  echo "No new Git commit is required."
  echo

  CHANGE_DESCRIPTION="Redeploy existing Fixxir source"
  DESCRIPTION="${CHANGE_DESCRIPTION} - ${TIMESTAMP}"
  COMMIT_MESSAGE=""

fi

echo "Deployment ID:"
echo "$DEPLOYMENT_ID"
echo
echo "Deployment description:"
echo "$DESCRIPTION"
echo

# ==========================================================
# 3. Show clasp files
# ==========================================================

echo "------------------------------------------------------"
echo "3. Files clasp will push"
echo "------------------------------------------------------"

clasp status

echo

if [[ "$HAS_CHANGES" == true ]]; then
  read -r -p "Commit and deploy these changes? [y/N]: " CONFIRM
else
  read -r -p "No Git changes. Deploy the current source anyway? [y/N]: " CONFIRM
fi

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
  echo
  echo "Deployment cancelled."
  exit 0
fi

# ==========================================================
# 4. Git commit only when there are changes
# ==========================================================

if [[ "$HAS_CHANGES" == true ]]; then

  echo
  echo "------------------------------------------------------"
  echo "4. Creating Git commit"
  echo "------------------------------------------------------"

  git add -A

  echo
  echo "Files being committed:"
  git status --short

  echo
  echo "Commit message:"
  echo "$COMMIT_MESSAGE"
  echo

  git commit -m "$COMMIT_MESSAGE"

  echo
  echo "Git commit created successfully."

else

  echo
  echo "------------------------------------------------------"
  echo "4. Git commit"
  echo "------------------------------------------------------"
  echo
  echo "No changes detected."
  echo "Skipping Git commit."

fi

# ==========================================================
# 5. Show commit being deployed
# ==========================================================

echo
echo "------------------------------------------------------"
echo "5. Git commit being deployed"
echo "------------------------------------------------------"

git log -1 --oneline

# ==========================================================
# 6. Push source
# ==========================================================

echo
echo "------------------------------------------------------"
echo "6. Pushing source to Apps Script"
echo "------------------------------------------------------"

clasp push

# ==========================================================
# 7. Create Apps Script version
# ==========================================================

echo
echo "------------------------------------------------------"
echo "7. Creating immutable Apps Script version"
echo "------------------------------------------------------"

VERSION_OUTPUT="$(clasp version "$DESCRIPTION")"

echo "$VERSION_OUTPUT"

VERSION_NUMBER="$(
  echo "$VERSION_OUTPUT" |
  grep -Eo '[0-9]+' |
  tail -1
)"

if [[ -z "$VERSION_NUMBER" ]]; then
  echo
  echo "ERROR: Could not determine newly-created version number."
  echo "The production deployment was NOT updated."
  exit 1
fi

echo
echo "Created Apps Script version: $VERSION_NUMBER"

# ==========================================================
# 8. Update existing deployment
# ==========================================================

echo
echo "------------------------------------------------------"
echo "8. Updating EXISTING Fixxir deployment"
echo "------------------------------------------------------"

clasp deploy \
  --deploymentId "$DEPLOYMENT_ID" \
  --versionNumber "$VERSION_NUMBER" \
  --description "$DESCRIPTION"

# ==========================================================
# 9. Verify deployment
# ==========================================================

echo
echo "------------------------------------------------------"
echo "9. Deployment status"
echo "------------------------------------------------------"

clasp deployments

# ==========================================================
# Final summary
# ==========================================================

echo
echo "======================================================"
echo " Fixxir Operations Deployment Complete"
echo "======================================================"
echo
echo "Change:"
echo "$CHANGE_DESCRIPTION"
echo
echo "Git commit:"
git log -1 --oneline
echo
echo "Apps Script version:"
echo "$VERSION_NUMBER"
echo
echo "Deployment ID:"
echo "$DEPLOYMENT_ID"
echo
echo "Web App URL:"
echo "https://script.google.com/macros/s/$DEPLOYMENT_ID/exec"
echo
echo "======================================================"