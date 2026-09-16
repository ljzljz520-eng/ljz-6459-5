"""API DTO (Pydantic)。操作员登记 -> 确认 -> 执行 -> 实验室回填 -> 放行。"""
from __future__ import annotations

from pydantic import BaseModel, Field, model_validator

from .models import (
    AnomalyKind,
    AnomalyStatus,
    ArcKind,
    BatchStatus,
    ReleaseDecision,
    StageKind,
)


class PartIn(BaseModel):
    part_no: str = Field(...)
    material: str = Field(..., description="材质, 如 42CrMo")
    pretreatment: str = Field(..., description="前处理, 如 调质+除油")
    fixture_position: str = Field(..., description="装夹位置, 如 上层A3")


class WitnessSampleIn(BaseModel):
    sample_no: str = Field(..., description="见证样编号")
    material: str = Field(...)
    fixture_position: str = Field(...)


class WitnessLoadIn(BaseModel):
    """装炉确认: 实际装上的见证样。"""

    sample_no: str
    fixture_position: str


class BatchCreateIn(BaseModel):
    furnace_id: str = Field(...)
    operator: str = Field(...)
    procedure_id: str = Field(..., description="批准程序(工艺规程)编号")
    parts: list[PartIn] = Field(...)
    witness_samples: list[WitnessSampleIn] = Field(..., description="计划见证样")


class LoadConfirmIn(BaseModel):
    """装炉确认: 操作员确认实际装夹的见证样。"""

    loaded_witness: list[WitnessLoadIn]


class ChecklistIn(BaseModel):
    gas_line_confirmed: bool = False
    insulation_confirmed: bool = False
    gas_channel_mapping: dict[str, str] = Field(
        default_factory=dict,
        description="物理通道映射, 如 {'MFC1':'N2','MFC2':'H2','MFC3':'Ar'}",
    )


class StageSpecIn(BaseModel):
    seq: int = Field(..., ge=0)
    kind: StageKind
    name: str
    duration_s: float = Field(..., ge=0)
    temp_setpoint_c: float | None = None
    pressure_setpoint_pa: float | None = None
    gas_setpoints: dict[str, float] = Field(
        default_factory=dict, description="气体设定流量 sccm, 键为气体种类 N2/H2/Ar"
    )
    bias_voltage_v: float | None = None
    bias_current_limit_a: float | None = None
    max_micro_arc_rate_per_min: float = 6.0


class ProcedureIn(BaseModel):
    procedure_id: str
    revision: str = "A"
    approved_by: str = Field(..., description="批准人, 程序必须为已批准状态")
    stages: list[StageSpecIn] = Field(...)
    compound_layer_um_min: float = 0.0
    compound_layer_um_max: float = 30.0
    diffusion_layer_mm_min: float = 0.1
    diffusion_layer_mm_max: float = 0.6
    surface_hardness_hv_min: float = 0.0

    @model_validator(mode="after")
    def _seq_unique(self):
        seqs = [s.seq for s in self.stages]
        if len(seqs) != len(set(seqs)):
            raise ValueError("stage seq 重复")
        return self


class TelemetryPointIn(BaseModel):
    ts: float | None = None
    stage_seq: int
    pressure_pa: float | None = None
    flows_sccm: dict[str, float] = Field(
        default_factory=dict, description="按物理通道, 如 {'MFC1': 120.0}"
    )
    bias_voltage_v: float | None = None
    bias_current_a: float | None = None
    workpiece_temp_c: float | None = None
    control_temp_c: float | None = None


class ArcEventIn(BaseModel):
    ts: float | None = None
    stage_seq: int
    kind: ArcKind
    peak_current_a: float
    duration_ms: float = 1.0
    location_hint: str | None = None


class GlowImageIn(BaseModel):
    ts: float | None = None
    stage_seq: int
    image_uri: str
    mean_pixel_value: float = Field(
        ..., ge=0, le=255, description="平均灰度, 用于过曝判定"
    )
    note: str | None = None


class LabResultIn(BaseModel):
    sample_no: str
    metallography: str = Field(..., description="金相结论")
    microhardness_hv: list[float] = Field(..., description="显微硬度梯度")
    compound_layer_um: float = Field(..., ge=0, description="化合物层(白亮层)厚度 um")
    diffusion_layer_mm: float = Field(..., ge=0, description="扩散层深度 mm")


class ReleaseIn(BaseModel):
    engineer: str = Field(...)
    decision: ReleaseDecision
    comment: str = ""


class AnomalyDispositionIn(BaseModel):
    engineer: str = Field(...)
    disposition: str = Field(..., description="处置说明")


class AnomalyOut(BaseModel):
    anomaly_id: str
    batch_id: str
    kind: AnomalyKind
    status: AnomalyStatus
    detail: str
    stage_seq: int | None
    created_ts: float
    disposition: str | None = None


class BatchOut(BaseModel):
    batch_id: str
    furnace_id: str
    operator: str
    procedure_id: str
    status: BatchStatus
    parts: list[PartIn]
    witness_samples: list[WitnessSampleIn]
    loaded_witness: list[WitnessLoadIn]
    checklist: ChecklistIn
    created_ts: float
    started_ts: float | None = None
    completed_ts: float | None = None


class StageSummaryOut(BaseModel):
    stage_seq: int
    kind: StageKind | None = None
    name: str | None = None
    avg_pressure_pa: float | None = None
    avg_gas_ratio: dict[str, float] | None = None
    avg_bias_voltage_v: float | None = None
    avg_bias_current_a: float | None = None
    avg_workpiece_temp_c: float | None = None
    micro_arc_count: int = 0
    hard_arc_count: int = 0
    glow_image_uris: list[str] = Field(default_factory=list)
    suspect_tc: bool = False


class CorrelationOut(BaseModel):
    """核心追溯: 过程参数 <-> 最终层结果。"""

    batch_id: str
    status: BatchStatus
    stages: list[StageSummaryOut]
    lab_results: list[dict]
    anomalies: list[AnomalyOut]
    release: dict | None = None
