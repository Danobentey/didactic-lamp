#!/usr/bin/env bash

set -euo pipefail

# ==========================================================
# Fixxir Operations - Apps Script Deployment
# ==========================================================

DEPLOYMENT_ID="AKfycbwDPZdeaB2pO1JNgPt9edXPGnsaKHipIXIC1nd2AWSzrNHsjEWzkpHMACQpvFwra7Zg"

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
# 1. Verify clasp authentication BEFORE making a Git commit
# ==========================================================

echo "------------------------------------------------------"
echo "1. Verifying clasp authentication"
echo "------------------------------------------------------"

if ! AUTH_OUTPUT="$(clasp show-authorized-user 2>&1)"; then
  echo
  echo "$AUTH_OUTPUT"
  echo
  echo "ERROR: clasp is not authenticated."
  echo
  echo "Run:"
  echo "  npx clasp login"
  echo
  echo "Then verify:"
  echo "  npx clasp show-authorized-user"
  echo
  echo "No Git commit was created and nothing was deployed."
  exit 1
fi

echo "$AUTH_OUTPUT"
echo

# Also verify that the authenticated account can access this Apps Script project.
if ! PROJECT_OUTPUT="$(clasp list-deployments 2>&1)"; then
  echo "$PROJECT_OUTPUT"
  echo
  echo "ERROR: clasp is authenticated, but it could not access this Apps Script project."
  echo "Check the Google account, .clasp.json scriptId, and Apps Script API access."
  echo
  echo "No Git commit was created and nothing was deployed."
  exit 1
fi

echo "clasp authentication and project access verified."
echo

# ==========================================================
# 2. Check Git status
# ==========================================================

echo "------------------------------------------------------"
echo "2. Git working tree status"
echo "------------------------------------------------------"

git status --short

echo
echo "------------------------------------------------------"
echo "3. Git change summary"
echo "------------------------------------------------------"

git diff --stat

if [[ -n "$(git status --porcelain)" ]]; then
  HAS_CHANGES=true
else
  HAS_CHANGES=false
fi

# ==========================================================
# 3. Build deployment description
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
# 4. Show clasp files
# ==========================================================

echo "------------------------------------------------------"
echo "4. Files clasp will push"
echo "------------------------------------------------------"

clasp show-file-status

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
# 5. Git commit only when there are changes
# ==========================================================

if [[ "$HAS_CHANGES" == true ]]; then

  echo
  echo "------------------------------------------------------"
  echo "5. Creating Git commit"
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
  echo "5. Git commit"
  echo "------------------------------------------------------"
  echo
  echo "No changes detected."
  echo "Skipping Git commit."

fi

# ==========================================================
# 6. Show commit being deployed
# ==========================================================

echo
echo "------------------------------------------------------"
echo "6. Git commit being deployed"
echo "------------------------------------------------------"

git log -1 --oneline

# ==========================================================
# 7. Push source
# ==========================================================

echo
echo "------------------------------------------------------"
echo "7. Pushing source to Apps Script"
echo "------------------------------------------------------"

clasp push

# ==========================================================
# 8. Create immutable Apps Script version
# ==========================================================

echo
echo "------------------------------------------------------"
echo "8. Creating immutable Apps Script version"
echo "------------------------------------------------------"

VERSION_OUTPUT="$(clasp create-version "$DESCRIPTION")"

echo "$VERSION_OUTPUT"

VERSION_NUMBER="$(
  echo "$VERSION_OUTPUT" |
  grep -Eo '[0-9]+' |
  tail -1
)"

if [[ -z "$VERSION_NUMBER" ]]; then
  echo
  echo "ERROR: Could not determine the newly-created Apps Script version number."
  echo "Source was pushed, but the production deployment was NOT updated."
  exit 1
fi

echo
echo "Created Apps Script version: $VERSION_NUMBER"

# ==========================================================
# 9. Update existing deployment
# ==========================================================

echo
echo "------------------------------------------------------"
echo "9. Updating EXISTING Fixxir deployment"
echo "------------------------------------------------------"

clasp create-deployment \
  --deploymentId "$DEPLOYMENT_ID" \
  --versionNumber "$VERSION_NUMBER" \
  --description "$DESCRIPTION"

# ==========================================================
# 10. Verify deployment
# ==========================================================

echo
echo "------------------------------------------------------"
echo "10. Deployment status"
echo "------------------------------------------------------"

clasp list-deployments

# ==========================================================
# Final summary
# ==========================================================

WEB_APP_URL="https://script.google.com/macros/s/$DEPLOYMENT_ID/exec"

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
echo "$WEB_APP_URL"
echo
echo "======================================================"
