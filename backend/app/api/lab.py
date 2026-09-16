"""实验室回填 / 异常处置 / 工艺工程师放行 / 追溯关联。"""
from __future__ import annotations

from fastapi import APIRouter, Request

from ..schemas import AnomalyDispositionIn, LabResultIn, ReleaseIn

router = APIRouter(tags=["lab"])


@router.post("/batches/{batch_id}/lab-results", status_code=201)
def backfill_lab(batch_id: str, body: LabResultIn, request: Request):
    return request.app.state.c.lab.backfill(batch_id, body)


@router.get("/batches/{batch_id}/lab-results")
def lab_results(batch_id: str, request: Request):
    return request.app.state.c.meta.lab_results(batch_id)


@router.get("/batches/{batch_id}/anomalies")
def anomalies(batch_id: str, request: Request):
    return request.app.state.c.meta.anomalies(batch_id)


@router.post("/anomalies/{anomaly_id}/disposition")
def disposition(anomaly_id: str, body: AnomalyDispositionIn, request: Request):
    ok = request.app.state.c.meta.disposition_anomaly(
        anomaly_id, body.engineer, body.disposition
    )
    return {"dispositioned": ok}


@router.post("/batches/{batch_id}/release")
def release(batch_id: str, body: ReleaseIn, request: Request):
    return request.app.state.c.lab.release(batch_id, body)


@router.get("/batches/{batch_id}/correlation")
def correlation(batch_id: str, request: Request):
    c = request.app.state.c
    batch = c.batches._require(batch_id)
    proc = c.meta.get_procedure(batch["procedure_id"]) or {}
    mapping = batch["checklist"].get("gas_channel_mapping", {})
    stages = []
    for spec in proc.get("stages", []):
        summary = c.telemetry.stage_summary(batch_id, spec["seq"], mapping)
        summary["kind"] = spec["kind"]
        summary["name"] = spec["name"]
        stages.append(summary)
    return {
        "batch_id": batch_id,
        "status": batch["status"].value,
        "stages": stages,
        "lab_results": c.meta.lab_results(batch_id),
        "anomalies": c.meta.anomalies(batch_id),
        "release": c.meta.latest_release(batch_id),
    }
