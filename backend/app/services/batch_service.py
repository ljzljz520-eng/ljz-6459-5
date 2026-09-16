"""批次登记 / 装炉确认 / 气路绝缘确认 / 执行批准程序。"""
from __future__ import annotations

from ..db import MetadataStore
from ..models import AnomalyKind, BatchStatus, StageKind, now_ts
from ..schemas import (
    BatchCreateIn,
    ChecklistIn,
    LoadConfirmIn,
    ProcedureIn,
    WitnessLoadIn,
)


class DomainError(Exception):
    """业务规则违例 -> HTTP 409/422。"""

    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


class BatchService:
    def __init__(self, store: MetadataStore):
        self.store = store

    def register_procedure(self, proc: ProcedureIn) -> dict:
        self.store.save_procedure(proc.model_dump())
        return {"procedure_id": proc.procedure_id, "revision": proc.revision}

    def create_batch(self, body: BatchCreateIn) -> dict:
        proc = self.store.get_procedure(body.procedure_id)
        if proc is None:
            raise DomainError(
                "PROCEDURE_NOT_FOUND", f"批准程序 {body.procedure_id} 不存在"
            )
        payload = {
            "parts": [p.model_dump() for p in body.parts],
            "witness_samples": [w.model_dump() for w in body.witness_samples],
            "loaded_witness": [],
            "checklist": ChecklistIn().model_dump(),
        }
        batch_id = self.store.create_batch(
            furnace_id=body.furnace_id,
            operator=body.operator,
            procedure_id=body.procedure_id,
            procedure_revision=proc.get("revision", "A"),
            payload=payload,
        )
        return self._require(batch_id)

    def _require(self, batch_id: str) -> dict:
        batch = self.store.get_batch(batch_id)
        if batch is None:
            raise DomainError("BATCH_NOT_FOUND", f"批次 {batch_id} 不存在")
        return batch

    def confirm_loading(self, batch_id: str, body: LoadConfirmIn) -> dict:
        batch = self._require(batch_id)
        self._require_status(batch, BatchStatus.DRAFT)
        planned = {w["sample_no"]: w for w in batch["witness_samples"]}
        loaded_nos = [w.sample_no for w in body.loaded_witness]
        missing = [no for no in planned if no not in loaded_nos]
        if missing:
            self.store.add_anomaly(
                batch_id,
                AnomalyKind.WITNESS_MISSING,
                f"见证样漏装: {', '.join(missing)} 未在装夹确认中出现",
            )
            raise DomainError(
                "WITNESS_MISSING",
                f"见证样漏装: {', '.join(missing)}; 请补装或由工艺工程师处置偏差",
            )
        unknown = [no for no in loaded_nos if no not in planned]
        if unknown:
            raise DomainError(
                "WITNESS_UNKNOWN", f"未登记的见证样编号: {', '.join(unknown)}"
            )
        payload = self._payload(batch)
        payload["loaded_witness"] = [w.model_dump() for w in body.loaded_witness]
        self.store.update_batch_payload(batch_id, payload)
        return self._require(batch_id)

    def confirm_checklist(self, batch_id: str, body: ChecklistIn) -> dict:
        batch = self._require(batch_id)
        self._require_status(batch, BatchStatus.DRAFT)
        if not batch["loaded_witness"]:
            raise DomainError("LOADING_NOT_CONFIRMED", "尚未完成装炉确认")
        if not body.gas_line_confirmed:
            raise DomainError("GAS_LINE_UNCONFIRMED", "气路未确认")
        if not body.insulation_confirmed:
            raise DomainError("INSULATION_UNCONFIRMED", "绝缘未确认")
        if not body.gas_channel_mapping:
            raise DomainError(
                "GAS_MAPPING_REQUIRED", "必须登记物理气体通道映射(如 MFC1->N2)"
            )
        payload = self._payload(batch)
        payload["checklist"] = body.model_dump()
        self.store.update_batch_payload(batch_id, payload)
        self.store.set_status(batch_id, BatchStatus.CHECKED)
        return self._require(batch_id)

    def start_run(self, batch_id: str) -> dict:
        batch = self._require(batch_id)
        self._require_status(batch, BatchStatus.CHECKED)
        open_witness = self.store.open_anomaly_of_kind(
            batch_id, AnomalyKind.WITNESS_MISSING
        )
        if open_witness:
            raise DomainError(
                "WITNESS_DEVIATION_OPEN", "见证样漏装偏差未处置, 禁止执行程序"
            )
        self.store.set_status(batch_id, BatchStatus.RUNNING)
        return self._require(batch_id)

    def complete_run(self, batch_id: str) -> dict:
        batch = self._require(batch_id)
        self._require_status(batch, BatchStatus.RUNNING)
        self.store.set_status(batch_id, BatchStatus.COMPLETED)
        return self._require(batch_id)

    @staticmethod
    def _payload(batch: dict) -> dict:
        return {
            "parts": batch["parts"],
            "witness_samples": batch["witness_samples"],
            "loaded_witness": batch["loaded_witness"],
            "checklist": batch["checklist"],
        }

    @staticmethod
    def _require_status(batch: dict, status: BatchStatus) -> None:
        if batch["status"] != status:
            raise DomainError(
                "BAD_STATE",
                f"批次当前状态 {batch['status'].value}, 要求 {status.value}",
            )
