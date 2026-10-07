# PoC evidence — privileged CI on untrusted PR code (replica)

Local replica of a real-world CI pattern.

## State 1 — as-written (vulnerable)

Run **37627725966**, event `issue_comment`, trigger `/run-integration` by the repo OWNER:

```
LEAKED_KEY_B64=***
LEAKED_KEY_HEX=7b2274797065223a22736572766963655f6163636f756e74222c2270726f6a6563745f6964223a22…
[benign] service account client for project=poc-demo
```

- `LEAKED_KEY_B64` came back as `***` → **GitHub masking catches base64.** (My draft originally
  claimed the opposite; the PoC disproved it.)
- `LEAKED_KEY_HEX` (hex, 458 chars) decoded byte-for-byte to the secret:
```
{"type":"service_account","project_id":"poc-demo","private_key_id":"DUMMYKEYID","private_key":"-----BEGIN PRIVATE KEY-----\nDUMMY-NOT-A-REAL-KEY\n-----END PRIVATE KEY-----\n","client_email":"poc@poc-demo.iam.gserviceaccount.com"}
```
- The script that produced it is the PR's version, served from `refs/pull/1/head`
  (`gh api repos/…/contents/.github/scripts/upload_test_results.py?ref=refs/pull/1/head` →
  the base64+hex lines; PR diff: `.github/scripts/upload_test_results.py +5/-0`).
- The job never lacked the secret: with it absent the script exits 1, and the step concluded
  `success` while printing `project=poc-demo` parsed from the key.

## State 2 — robust fix (falsifier)

`falsifier/base_ref_script.patch` makes the secret-bearing step fetch the uploader **from the base
branch** instead of the PR tree (fork-ness is irrelevant to this fix).

Run **37627855724**, same trigger: `LEAKED_KEY_HEX` present? **0 occurrences**; the base branch's
script ran normally (`[benign] service account client for project=poc-demo`).

⇒ vulnerable leaks the inherited secret; fixed does not, while the suite still works.

## Note on the other fix

`falsifier/fork_guard.patch` (reject fork PRs at runtime) is the fix `verify.yml:99-181` uses
upstream. It is **not** testable in this replica: a single GitHub account can only open
same-repo PRs, so `head.repo.fork` is `false` and the guard would correctly allow them. Against a
real fork PR it blocks the path; against a *same-repo* PR by a less-trusted collaborator it does not
— which is why the base-ref fix above is the one to lead with.
