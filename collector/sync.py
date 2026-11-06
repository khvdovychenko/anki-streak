"""Download a fresh read-only copy of the Anki collection from AnkiWeb.

Safety: this script only ever DOWNLOADS. It never uploads, so it cannot
overwrite or damage the real collection on AnkiWeb or on your phone.
"""
import os
import shutil
import sys
from pathlib import Path

from anki.collection import Collection
from anki.sync_pb2 import SyncCollectionResponse

ROOT = Path(__file__).resolve().parent.parent
WORK_DIR = ROOT / "data" / "anki"
COLLECTION_PATH = WORK_DIR / "collection.anki2"

ChangesRequired = SyncCollectionResponse.ChangesRequired


def download_collection() -> Path:
    username = os.environ.get("ANKI_USERNAME")
    password = os.environ.get("ANKI_PASSWORD")
    if not username or not password:
        sys.exit("ANKI_USERNAME and ANKI_PASSWORD must be set (GitHub secrets).")

    # Always start from an empty local collection, so AnkiWeb asks us
    # for a full download and nothing local can ever be sent upstream.
    shutil.rmtree(WORK_DIR, ignore_errors=True)
    WORK_DIR.mkdir(parents=True)

    col = Collection(str(COLLECTION_PATH))
    try:
        auth = col.sync_login(username=username, password=password, endpoint=None)
        out = col.sync_collection(auth=auth, sync_media=False)
        if out.new_endpoint:
            auth.endpoint = out.new_endpoint

        if out.required in (ChangesRequired.FULL_DOWNLOAD, ChangesRequired.FULL_SYNC):
            # full_upload_or_download closes the collection itself.
            col.full_upload_or_download(auth=auth, server_usn=None, upload=False)
            col = None
        elif out.required == ChangesRequired.FULL_UPLOAD:
            sys.exit("AnkiWeb looks empty. Refusing to upload anything. Check the account.")
        else:
            sys.exit(f"Unexpected sync state: {out.required}")
    finally:
        if col is not None:
            col.close()

    print(f"Downloaded collection: {COLLECTION_PATH.stat().st_size / 1e6:.1f} MB")
    return COLLECTION_PATH


if __name__ == "__main__":
    download_collection()
