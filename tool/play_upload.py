"""Upload the release AAB to Google Play's internal testing track.

Usage: PLAY_STORE_CONFIG_JSON=<service account JSON> play_upload.py <aab> <versionCode>

The service account (the one of guettli/sharedinbox, see README "Google
Play") may release to testing tracks only. Run by CI after each release.
"""

import json
import os
import sys

import requests
from google.auth.transport.requests import AuthorizedSession, Request
from google.oauth2 import service_account

PACKAGE = "de.sharedinbox.pp2"
TRACK = "internal"
API = "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/" + PACKAGE
UPLOAD = "https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/" + PACKAGE


def check(r: requests.Response, what: str) -> requests.Response:
    if not r.ok:
        sys.exit(f"{what}: HTTP {r.status_code}: {r.text[:1000]}")
    return r


def main() -> None:
    aab, version = sys.argv[1], sys.argv[2]
    creds = service_account.Credentials.from_service_account_info(
        json.loads(os.environ["PLAY_STORE_CONFIG_JSON"]),
        scopes=["https://www.googleapis.com/auth/androidpublisher"],
    )
    s = AuthorizedSession(creds)
    edit = check(s.post(f"{API}/edits", timeout=60), "create edit").json()["id"]
    try:
        # a re-run of the release job has the same versionCode: done already
        bundles = check(s.get(f"{API}/edits/{edit}/bundles", timeout=60), "list bundles").json()
        if any(str(b["versionCode"]) == version for b in bundles.get("bundles", [])):
            print(f"versionCode {version} was uploaded before")
            return
        # resumable: the bundle is ~150 MB
        size = os.path.getsize(aab)
        r = check(
            s.post(
                f"{UPLOAD}/edits/{edit}/bundles?uploadType=resumable",
                headers={"X-Upload-Content-Type": "application/octet-stream", "X-Upload-Content-Length": str(size)},
                timeout=60,
            ),
            "start upload",
        )
        # plain requests, fresh token: AuthorizedSession would resend after a
        # 401 with the file already read
        creds.refresh(Request())
        with open(aab, "rb") as f:
            got = check(
                requests.put(
                    r.headers["Location"],
                    data=f,
                    headers={"Content-Type": "application/octet-stream", "Authorization": "Bearer " + creds.token},
                    timeout=1200,
                ),
                "upload bundle",
            ).json()
        if str(got["versionCode"]) != version:
            sys.exit(f"uploaded versionCode {got['versionCode']}, expected {version}")
        check(
            s.put(
                f"{API}/edits/{edit}/tracks/{TRACK}",
                json={"track": TRACK, "releases": [{"versionCodes": [version], "status": "completed"}]},
                timeout=60,
            ),
            "assign track",
        )
        check(s.post(f"{API}/edits/{edit}:commit", timeout=120), "commit")
        edit = None
        print(f"versionCode {version} is on the {TRACK} track")
    finally:
        if edit:
            try:
                s.delete(f"{API}/edits/{edit}", timeout=60)
            except requests.RequestException as e:
                print("could not discard the edit:", e)


if __name__ == "__main__":
    main()
