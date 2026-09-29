"""Private photo storage. Files are never public: after the ownership check the
API hands out a short-lived signed URL."""

import hashlib
import hmac
import time
import uuid
from pathlib import Path
from urllib.parse import urlencode

from ..config import get_settings

ALLOWED_TYPES = {"image/jpeg": ".jpg", "image/png": ".png", "image/webp": ".webp"}
_MAGIC = {b"\xff\xd8\xff": "image/jpeg", b"\x89PNG\r\n\x1a\n": "image/png"}


def sniff_image_type(head: bytes) -> str | None:
    for magic, ctype in _MAGIC.items():
        if head.startswith(magic):
            return ctype
    if head[:4] == b"RIFF" and head[8:12] == b"WEBP":
        return "image/webp"
    return None


def new_photo_key(user_id: uuid.UUID, content_type: str) -> str:
    return f"memory-book/{user_id}/{uuid.uuid4()}{ALLOWED_TYPES[content_type]}"


def key_owner(key: str) -> uuid.UUID | None:
    parts = key.split("/")
    if len(parts) != 3 or parts[0] != "memory-book":
        return None
    try:
        return uuid.UUID(parts[1])
    except ValueError:
        return None


def _s3():
    import boto3

    s = get_settings()
    return boto3.client(
        "s3",
        endpoint_url=s.s3_endpoint_url,
        region_name=s.s3_region,
        aws_access_key_id=s.s3_access_key.get_secret_value() if s.s3_access_key else None,
        aws_secret_access_key=s.s3_secret_key.get_secret_value() if s.s3_secret_key else None,
    )


def put_object(key: str, data: bytes, content_type: str) -> None:
    s = get_settings()
    if s.storage_backend == "s3":
        _s3().put_object(Bucket=s.s3_bucket, Key=key, Body=data, ContentType=content_type)
        return
    path = Path(s.storage_local_dir) / key
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


def _local_sig(key: str, expires: int) -> str:
    secret = get_settings().jwt_secret.get_secret_value().encode()
    return hmac.new(secret, f"{key}:{expires}".encode(), hashlib.sha256).hexdigest()


def signed_url(key: str) -> str:
    s = get_settings()
    if s.storage_backend == "s3":
        return _s3().generate_presigned_url(
            "get_object", Params={"Bucket": s.s3_bucket, "Key": key}, ExpiresIn=s.signed_url_seconds
        )
    expires = int(time.time()) + s.signed_url_seconds
    return f"{s.public_base_url}/files/{key}?" + urlencode({"expires": expires, "sig": _local_sig(key, expires)})


def verify_local_signature(key: str, expires: int, sig: str) -> bool:
    return expires >= time.time() and hmac.compare_digest(_local_sig(key, expires), sig)


def local_path(key: str) -> Path:
    base = Path(get_settings().storage_local_dir).resolve()
    path = (base / key).resolve()
    if base not in path.parents:
        raise ValueError("bad key")
    return path
