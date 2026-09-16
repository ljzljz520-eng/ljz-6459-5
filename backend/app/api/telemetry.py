"""炉体时序接入与阶段查询。"""
from __future__ import annotations

from fastapi import APIRouter, Request

from ..schemas import ArcEventIn, GlowImageIn, TelemetryPointIn

router = APIRouter(tags=["telemetry"])


@router.post("/batches/{batch_id}/telemetry", status_code=202)
def ingest_telemetry(batch_id: str, body: TelemetryPointIn, request: Request):
    return request.app.state.c.telemetry.ingest_telemetry(batch_id, body)


@router.post("/batches/{batch_id}/arcs", status_code=202)
def ingest_arc(batch_id: str, body: ArcEventIn, request: Request):
    return request.app.state.c.telemetry.ingest_arc(batch_id, body)


@router.post("/batches/{batch_id}/glow-images", status_code=202)
def ingest_glow(batch_id: str, body: GlowImageIn, request: Request):
    return request.app.state.c.telemetry.ingest_glow_image(batch_id, body)


@router.get("/batches/{batch_id}/stages/{stage_seq}/series")
def stage_series(batch_id: str, stage_seq: int, request: Request):
    return request.app.state.c.telemetry.stage_series(batch_id, stage_seq)


@router.get("/batches/{batch_id}/arcs")
def arc_events(batch_id: str, request: Request, stage_seq: int | None = None):
    return request.app.state.c.telemetry.arc_events(batch_id, stage_seq)


@router.get("/batches/{batch_id}/glow-images")
def glow_images(batch_id: str, request: Request, stage_seq: int | None = None):
    return request.app.state.c.telemetry.glow_images(batch_id, stage_seq)


@router.post("/batches/{batch_id}/stages/{stage_seq}/checks")
def run_stage_checks(batch_id: str, stage_seq: int, request: Request):
    c = request.app.state.c
    batch = c.batches._require(batch_id)
    proc = c.meta.get_procedure(batch["procedure_id"])
    stage = next(s for s in proc.get("stages", []) if s["seq"] == stage_seq)
    mapping = batch["checklist"].get("gas_channel_mapping", {})
    gas = c.anomalies.check_gas_channels(
        batch_id, stage_seq, stage.get("gas_setpoints", {}), mapping
    )
    tc = c.anomalies.check_thermocouple(batch_id, stage_seq)
    micro = c.anomalies.check_micro_arc_rate(
        batch_id, stage_seq, stage.get("max_micro_arc_rate_per_min", 6.0)
    )
    return {"gas_channels": gas, "thermocouple": tc, "micro_arcs": micro}
