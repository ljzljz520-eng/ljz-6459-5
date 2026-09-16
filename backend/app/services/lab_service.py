"""实验室回填与工艺工程师放行。"""
from __future__ import annotations

from ..db import MetadataStore
from ..models import AnomalyStatus, BatchStatus, ReleaseDecision
from ..schemas import LabResultIn, ReleaseIn
from .batch_service import DomainError


class LabService:
    def __init__(self, store: MetadataStore):
        self.store = store

    def backfill(self, batch_id: str, body: LabResultIn) -> dict:
        batch = self._batch(batch_id)
        if batch["status"] not in (
            BatchStatus.COMPLETED,
            BatchStatus.LAB_PARTIAL,
            BatchStatus.LAB_COMPLETE,
        ):
            raise DomainError("BAD_STATE", "批次未出炉, 不能回填实验室结果")
        loaded = {w["sample_no"] for w in batch["loaded_witness"]}
        if body.sample_no not in loaded:
            raise DomainError(
                "SAMPLE_NOT_LOADED",
                f"见证样 {body.sample_no} 不在本批次装炉清单中",
            )
        self.store.upsert_lab_result(batch_id, body.sample_no, body.model_dump())
        done = {r["sample_no"] for r in self.store.lab_results(batch_id)}
        if loaded and loaded <= done:
            self.store.set_status(batch_id, BatchStatus.LAB_COMPLETE)
        else:
            self.store.set_status(batch_id, BatchStatus.LAB_PARTIAL)
        return {
            "sample_no": body.sample_no,
            "complete": loaded <= done,
        }

    def release(self, batch_id: str, body: ReleaseIn) -> dict:
        batch = self._batch(batch_id)
        if batch["status"] not in (BatchStatus.LAB_COMPLETE, BatchStatus.HOLD):
            raise DomainError("BAD_STATE", "实验室结果未齐全, 不能放行判定")
        proc = self.store.get_procedure(batch["procedure_id"]) or {}
        results = self.store.lab_results(batch_id)

        failures: list[str] = []
        for r in results:
            if not (
                proc.get("compound_layer_um_min", 0)
                <= r["compound_layer_um"]
                <= proc.get("compound_layer_um_max", 1_000_000_000.0)
            ):
                failures.append(
                    f"{r['sample_no']} 化合物层 {r['compound_layer_um']}um 超窗"
                )
            if not (
                proc.get("diffusion_layer_mm_min", 0)
                <= r["diffusion_layer_mm"]
                <= proc.get("diffusion_layer_mm_max", 1_000_000_000.0)
            ):
                failures.append(
                    f"{r['sample_no']} 扩散层 {r['diffusion_layer_mm']}mm 超窗"
                )
            hv_min = proc.get("surface_hardness_hv_min", 0)
            if hv_min and max(r["microhardness_hv"]) < hv_min:
                failures.append(
                    f"{r['sample_no']} 表面硬度低于 {hv_min}HV"
                )

        open_anomalies = [
            a
            for a in self.store.anomalies(batch_id)
            if a["status"] != AnomalyStatus.DISPOSITIONED.value
        ]

        if body.decision == ReleaseDecision.RELEASED:
            if failures:
                raise DomainError("SPEC_FAILURE", "; ".join(failures))
            if open_anomalies:
                kinds = ", ".join(str(a["kind"]) for a in open_anomalies)
                raise DomainError(
                    "ANOMALY_OPEN", f"存在未处置异常({kinds}), 禁止放行"
                )

        self.store.add_release(
            batch_id, body.engineer, body.decision, body.comment
        )
        self.store.set_status(batch_id, BatchStatus(body.decision.value))
        return {
            "batch_id": batch_id,
            "decision": body.decision.value,
            "spec_failures": failures,
        }

    def _batch(self, batch_id: str) -> dict:
        batch = self.store.get_batch(batch_id)
        if batch is None:
            raise DomainError("BATCH_NOT_FOUND", f"批次 {batch_id} 不存在")
        return batch
