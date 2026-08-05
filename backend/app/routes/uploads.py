import os
import uuid
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, status
from typing import List

from app import models, auth

router = APIRouter(prefix="/uploads", tags=["Uploads"])

UPLOAD_DIR = os.getenv("UPLOAD_DIR", "/app/uploads/vehicles")
MAX_FILE_SIZE_BYTES = 5 * 1024 * 1024  # 5MB
ALLOWED_MIME_TYPES = {"image/jpeg", "image/png", "image/webp"}
ALLOWED_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp"}


def _ensure_upload_dir():
    os.makedirs(UPLOAD_DIR, exist_ok=True)


@router.post("/vehicle-main-image")
async def upload_vehicle_main_image(
    file: UploadFile = File(...),
    current_user: models.User = Depends(auth.RoleChecker(["owner", "admin"]))
):
    """Upload main image for a vehicle."""
    _ensure_upload_dir()

    # 1. Validate MIME type
    if file.content_type not in ALLOWED_MIME_TYPES:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid file type: {file.content_type}. Only JPEG, PNG, and WebP images are allowed."
        )

    # 2. Extract and validate extension
    _, ext = os.path.splitext(file.filename or "")
    ext = ext.lower()
    if ext not in ALLOWED_EXTENSIONS:
        ext = ".jpg" if file.content_type == "image/jpeg" else ".png"

    # 3. Read content & validate file size
    contents = await file.read()
    if len(contents) > MAX_FILE_SIZE_BYTES:
        raise HTTPException(
            status_code=400,
            detail="File size exceeds maximum allowed limit of 5MB."
        )

    # 4. Generate unguessable UUID filename
    filename = f"main_{uuid.uuid4().hex}{ext}"
    filepath = os.path.join(UPLOAD_DIR, filename)

    # Sanitize path safety check
    resolved_path = os.path.abspath(filepath)
    resolved_dir = os.path.abspath(UPLOAD_DIR)
    if not resolved_path.startswith(resolved_dir):
        raise HTTPException(status_code=400, detail="Invalid target filename path.")

    # 5. Write file to disk
    with open(filepath, "wb") as f:
        f.write(contents)

    public_url = f"/uploads/vehicles/{filename}"
    return {"url": public_url, "filename": filename}


@router.post("/vehicle-gallery")
async def upload_vehicle_gallery_images(
    files: List[UploadFile] = File(...),
    current_user: models.User = Depends(auth.RoleChecker(["owner", "admin"]))
):
    """Upload gallery images for a vehicle (max 5 files)."""
    if len(files) > 5:
        raise HTTPException(
            status_code=400,
            detail="You can upload at most 5 gallery photos."
        )

    _ensure_upload_dir()
    uploaded_urls = []

    for file in files:
        if file.content_type not in ALLOWED_MIME_TYPES:
            continue

        _, ext = os.path.splitext(file.filename or "")
        ext = ext.lower()
        if ext not in ALLOWED_EXTENSIONS:
            ext = ".jpg"

        contents = await file.read()
        if len(contents) > MAX_FILE_SIZE_BYTES:
            continue

        filename = f"gallery_{uuid.uuid4().hex}{ext}"
        filepath = os.path.join(UPLOAD_DIR, filename)

        resolved_path = os.path.abspath(filepath)
        resolved_dir = os.path.abspath(UPLOAD_DIR)
        if not resolved_path.startswith(resolved_dir):
            continue

        with open(filepath, "wb") as f:
            f.write(contents)

        uploaded_urls.append(f"/uploads/vehicles/{filename}")

    return {"urls": uploaded_urls}
