import logging
from dataclasses import dataclass

import boto3
from botocore.client import Config

from app.core.config import get_settings

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class PresignedUrl:
    url: str
    headers: dict[str, str]


class ObjectStorage:
    def __init__(self) -> None:
        self.settings = get_settings()
        self.bucket = self.settings.s3_bucket
        self._client = None

    @property
    def client(self):
        if self._client is None:
            self._client = boto3.client(
                "s3",
                endpoint_url=self.settings.s3_endpoint_url,
                aws_access_key_id=self.settings.s3_access_key_id,
                aws_secret_access_key=self.settings.s3_secret_access_key,
                region_name=self.settings.s3_region,
                config=Config(signature_version="s3v4"),
            )
        return self._client

    def ensure_bucket(self) -> None:
        if self.settings.object_storage_backend != "minio":
            return
        try:
            self.client.head_bucket(Bucket=self.bucket)
        except Exception:
            logger.info("Creating object bucket %s", self.bucket)
            self.client.create_bucket(Bucket=self.bucket)

    def presign_put(self, object_key: str, content_length: int, checksum: str | None = None) -> PresignedUrl:
        if self.settings.object_storage_backend != "minio":
            return PresignedUrl(
                url=f"http://local-object-storage.test/{self.bucket}/{object_key}",
                headers={"x-noir-local-size": str(content_length), **({"x-noir-checksum": checksum} if checksum else {})},
            )
        params = {"Bucket": self.bucket, "Key": object_key}
        url = self.client.generate_presigned_url(
            "put_object",
            Params=params,
            ExpiresIn=self.settings.upload_url_ttl_seconds,
        )
        return PresignedUrl(url=url, headers={})

    def presign_get(self, object_key: str) -> str:
        if self.settings.object_storage_backend != "minio":
            return f"http://local-object-storage.test/{self.bucket}/{object_key}"
        return self.client.generate_presigned_url(
            "get_object",
            Params={"Bucket": self.bucket, "Key": object_key},
            ExpiresIn=self.settings.download_url_ttl_seconds,
        )

    def delete_object(self, object_key: str) -> None:
        if self.settings.object_storage_backend != "minio":
            return
        self.client.delete_object(Bucket=self.bucket, Key=object_key)


storage = ObjectStorage()

