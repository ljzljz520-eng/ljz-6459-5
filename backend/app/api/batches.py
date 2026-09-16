"""批次登记 / 装炉确认 / 气路绝缘确认 / 程序执行。"""
from __future__ import annotations

from fastapi import APIRouter, Request

from ..schemas import BatchCreateIn, ChecklistIn, LoadConfirmIn, ProcedureIn

router = APIRouter(tags=["batches"])


@router.post("/procedures", status_code=201)
def register_procedure(body: ProcedureIn, request: Request):
    return request.app.state.c.batches.register_procedure(body)


@router.post("/batches", status_code=201)
def create_batch(body: BatchCreateIn, request: Request):
    return request.app.state.c.batches.create_batch(body)


@router.get("/batches")
def list_batches(request: Request):
    return request.app.state.c.meta.list_batches()


@router.get("/batches/{batch_id}")
def get_batch(batch_id: str, request: Request):
    return request.app.state.c.batches._require(batch_id)


@router.post("/batches/{batch_id}/loading")
def confirm_loading(batch_id: str, body: LoadConfirmIn, request: Request):
    return request.app.state.c.batches.confirm_loading(batch_id, body)


@router.post("/batches/{batch_id}/checklist")
def confirm_checklist(batch_id: str, body: ChecklistIn, request: Request):
    return request.app.state.c.batches.confirm_checklist(batch_id, body)


@router.post("/batches/{batch_id}/start")
def start_run(batch_id: str, request: Request):
    return request.app.state.c.batches.start_run(batch_id)


@router.post("/batches/{batch_id}/complete")
def complete_run(batch_id: str, request: Request):
    return request.app.state.c.batches.complete_run(batch_id)
