# Owner: Member A. All durable evidence bytes live in MongoDB GridFS.
import io;
import base64;
import binascii;
import hashlib;
import from PIL { Image, UnidentifiedImageError }
import from gridfs { GridFSBucket }
import from pymongo { ReturnDocument }
import from pymongo.errors { DuplicateKeyError }
import from data.connection { _get_database }
import from data.repositories { _get_case_record, _assert_revision, _assert_not_busy, _archive_assessment }
import from shared.config { _get_settings }
import from shared.contracts { FixoraError }
import from shared.validation { _identifier, _request_id, _text, _new_id, _now }

def _decode_image(content_base64: str) -> dict[str, any] {
    limit = _get_settings().max_file_bytes;
    if len(content_base64) > 4 * ((limit + 2) // 3) {
        raise FixoraError("VALIDATION_ERROR", "Image exceeds the 5 MB upload limit.");
    }
    try { raw = base64.b64decode(content_base64, validate=True); }
    except (ValueError, binascii.Error) {
        raise FixoraError("VALIDATION_ERROR", "Supply plain base64 image content without a data URL prefix.");
    }
    if not raw or len(raw) > limit { raise FixoraError("VALIDATION_ERROR", "Image is empty or exceeds 5 MB."); }
    try {
        image = Image.open(io.BytesIO(raw));
        image_format = image.format;
        if image_format not in ["PNG", "JPEG"] or (image.width as int) * (image.height as int) > 25000000 {
            image.close();
            raise FixoraError("VALIDATION_ERROR", "Use a JPEG/PNG image with at most 25 million pixels.");
        }
        image.verify();
        image.close();
    } except (UnidentifiedImageError, OSError, SyntaxError, EOFError, Image.DecompressionBombError) {
        raise FixoraError("VALIDATION_ERROR", "The upload is not a readable JPEG/PNG image.");
    }
    return {"bytes": raw, "mime_type": "image/png" if image_format == "PNG" else "image/jpeg",
        "sha256": hashlib.sha256(raw).hexdigest(), "size_bytes": len(raw)};
}

def _upload_image(case_id: str, expected_revision: int, kind: str, filename: str, content_base64: str, request_id: str) -> dict[str, any] {
    _request_id(request_id);
    if kind not in ["invoice", "product"] { raise FixoraError("VALIDATION_ERROR", "Evidence kind must be invoice or product."); }
    filename = _text(filename.replace("\\", "/").split("/")[-1], "Filename", 120);
    if "\r" in filename or "\n" in filename { raise FixoraError("VALIDATION_ERROR", "Filename contains invalid characters."); }
    image = _decode_image(content_base64);
    item = _get_case_record(case_id);
    database = _get_database();
    existing = database.evidence.find_one({"case_id": case_id, "request_id": request_id});
    if existing is not None {
        if existing["sha256"] != image["sha256"] or existing["kind"] != kind or existing["filename"] != filename {
            raise FixoraError("IDEMPOTENCY_CONFLICT", "This upload request ID was used with different input.");
        }
        if existing["_id"] not in item["evidence_ids"] {
            raise FixoraError("STAGE_BUSY", "This upload is being finalized. Retry shortly.");
        }
        return existing as dict[str, any];
    }
    _assert_revision(item, expected_revision);
    _assert_not_busy(item);
    records = list(database.evidence.find({"_id": {"$in": item["evidence_ids"]}, "case_id": case_id})) as list[dict[str, any]];
    count = len([record for record in records if record["kind"] == kind]);
    if count >= (1 if kind == "invoice" else 3) {
        raise FixoraError("VALIDATION_ERROR", "Evidence limit reached for this kind. Remove an old image before uploading another.");
    }
    _archive_assessment(item);
    bucket = GridFSBucket(database, bucket_name="uploads");
    file_id = bucket.upload_from_stream(filename, image["bytes"], metadata={"case_id": case_id, "mime_type": image["mime_type"]});
    evidence_id = _new_id();
    metadata: dict[str, any] = {"_id": evidence_id, "case_id": case_id, "request_id": request_id,
        "kind": kind, "filename": filename, "gridfs_id": file_id, "mime_type": image["mime_type"],
        "sha256": image["sha256"], "size_bytes": image["size_bytes"], "uploaded_at": _now()};
    inserted = False;
    try {
        database.evidence.insert_one(metadata);
        inserted = True;
        updated = database.cases.find_one_and_update({"_id": case_id, "revision": expected_revision},
            {"$push": {"evidence_ids": evidence_id}, "$inc": {"revision": 1},
                "$set": {"status": "draft", "assessment": None, "active_assessment_id": None,
                    "stage_lease": None, "review_status": "unreviewed", "review_assessment_id": None,
                    "owner_inspection": None, "updated_at": _now()}}, return_document=ReturnDocument.AFTER);
        if updated is None { raise FixoraError("STALE_REVISION", "Case changed during upload. Reload and retry."); }
    } except DuplicateKeyError {
        bucket.delete(file_id);
        raise FixoraError("STAGE_BUSY", "This upload request is already being finalized. Retry with the same request ID.");
    } except FixoraError {
        if inserted { database.evidence.delete_one({"_id": evidence_id}); }
        bucket.delete(file_id);
        raise;
    }
    return metadata;
}

def _read_image(case_id: str, evidence_id: str) -> dict[str, any] {
    _identifier(evidence_id, "Evidence ID");
    item = _get_case_record(case_id);
    if evidence_id not in item["evidence_ids"] { raise FixoraError("NOT_FOUND", "Evidence not found for this case."); }
    database = _get_database();
    metadata = database.evidence.find_one({"_id": evidence_id, "case_id": case_id});
    if metadata is None { raise FixoraError("NOT_FOUND", "Evidence metadata not found."); }
    stream = GridFSBucket(database, bucket_name="uploads").open_download_stream(metadata["gridfs_id"]);
    try { raw = stream.read(); }
    finally { stream.close(); }
    return {"evidence_id": evidence_id, "filename": metadata["filename"], "mime_type": metadata["mime_type"],
        "content_base64": base64.b64encode(raw).decode("ascii")};
}

def _remove_image(case_id: str, evidence_id: str, expected_revision: int) -> dict[str, any] {
    _identifier(evidence_id, "Evidence ID");
    item = _get_case_record(case_id);
    _assert_revision(item, expected_revision);
    _assert_not_busy(item);
    if evidence_id not in item["evidence_ids"] { raise FixoraError("NOT_FOUND", "Evidence not found for this case."); }
    _archive_assessment(item);
    # Unlink atomically. Keep original bytes/metadata as historical evidence for
    # archived assessments; removal is not a data-erasure endpoint.
    updated = _get_database().cases.find_one_and_update({"_id": case_id, "revision": expected_revision},
        {"$pull": {"evidence_ids": evidence_id}, "$inc": {"revision": 1},
            "$set": {"status": "draft", "assessment": None, "active_assessment_id": None,
                "stage_lease": None, "review_status": "unreviewed", "review_assessment_id": None,
                "owner_inspection": None, "updated_at": _now()}}, return_document=ReturnDocument.AFTER);
    if updated is None { raise FixoraError("STALE_REVISION", "Case changed while removing evidence. Reload and retry."); }
    return updated as dict[str, any];
}
