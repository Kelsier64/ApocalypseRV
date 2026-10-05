"""Local HTTP interface; instantiate with create_app for isolated deployments/tests."""
import pathlib
from contextlib import asynccontextmanager
from typing import Literal

from fastapi import FastAPI, File, Form, Header, HTTPException, UploadFile
from fastapi.responses import FileResponse, JSONResponse

from pipeline import InputError
from service import JobService, MAX_IMAGE_BYTES, ServiceError


def create_app(root=None, backend=None, start_worker=True):
    service = JobService(root or pathlib.Path(__file__).resolve().parent, backend)

    @asynccontextmanager
    async def lifespan(application):
        if start_worker:
            service.start()
        yield
        if start_worker:
            service.stop()

    application = FastAPI(title="Pixal3D Local Asset API V2", version="0.2.0", lifespan=lifespan)
    application.state.service = service

    @application.exception_handler(ServiceError)
    async def service_error(request, error):
        return JSONResponse(status_code=error.status_code, content={"detail": error.detail})

    @application.exception_handler(InputError)
    async def input_error(request, error):
        return JSONResponse(status_code=error.status_code, content={"detail": error.detail})

    async def read_image(upload):
        data = await upload.read(MAX_IMAGE_BYTES + 1)
        if len(data) > MAX_IMAGE_BYTES:
            raise HTTPException(413, "Each image must be at most 25 MiB")
        return data

    @application.get("/health")
    def health():
        result = service.health()
        return JSONResponse(result, status_code=200 if result["backend"]["available"] else 503)

    @application.post("/jobs", status_code=202)
    async def submit(image: UploadFile = File(...), asset_id: str = Form(...),
                     preset: Literal["preview512", "standard1024", "threeview512", "threeview1024"] = Form("preview512"),
                     seed: int = Form(42), fov: float | None = Form(None),
                     background: Literal["auto", "alpha", "black", "remove"] = Form("auto"),
                     idempotency_key: str | None = Header(None)):
        return service.submit({"image": await read_image(image)}, asset_id, preset, seed, fov, background, idempotency_key)

    @application.post("/jobs/multiview", status_code=202)
    async def multiview(front: UploadFile = File(...), left: UploadFile = File(...), back: UploadFile = File(...),
                        right: UploadFile | None = File(None), asset_id: str = Form(...),
                        preset: Literal["threeview512", "threeview1024"] = Form("threeview512"),
                        seed: int = Form(42), fov: float | None = Form(None),
                        background: Literal["auto", "alpha", "black", "remove"] = Form("auto"),
                        idempotency_key: str | None = Header(None)):
        images = {"front": await read_image(front), "left": await read_image(left), "back": await read_image(back)}
        if right:
            images["right"] = await read_image(right)
        return service.submit(images, asset_id, preset, seed, fov, background, idempotency_key)

    @application.get("/jobs/{job_id}")
    def status(job_id: str):
        return service.public_snapshot(job_id)

    @application.get("/jobs/{job_id}/result")
    def result(job_id: str):
        return service.result(job_id)

    @application.get("/jobs/{job_id}/result.glb")
    def download(job_id: str):
        path = service.artifact_path(job_id)
        return FileResponse(path, media_type="model/gltf-binary", filename=service.snapshot(job_id)["asset_id"] + ".glb")

    @application.get("/jobs/{job_id}/conditioning/{view}.png")
    def conditioning(job_id: str, view: str):
        return FileResponse(service.artifact_path(job_id, view), media_type="image/png", filename=view + ".png")

    @application.get("/jobs/{job_id}/inputs")
    def inputs(job_id: str):
        job = service.snapshot(job_id)
        if job.get("_legacy"):
            raise ServiceError(404, "Legacy jobs have no V2 normalized input metadata")
        return {"job_id": job_id, "metadata": job["inputs"],
                "download_urls": {view: f"/jobs/{job_id}/inputs/{view}.png" for view in job["input_views"]}}

    @application.get("/jobs/{job_id}/inputs/{view}.png")
    def input_download(job_id: str, view: str):
        return FileResponse(service.input_path(job_id, view), media_type="image/png", filename=view + ".png")

    return application


app = create_app()
