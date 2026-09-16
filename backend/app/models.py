"""离子氮化批次领域模型与枚举。

状态机:
  DRAFT -> CHECKED -> RUNNING -> COMPLETED -> LAB_PARTIAL -> LAB_COMPLETE
  LAB_COMPLETE -> RELEASED | REJECTED | HOLD   (工艺工程师放行)
"""
from __future__ import annotations

import enum
import time
import uuid


def new_id(prefix: str) -> str:
    return f"{prefix}-{uuid.uuid4().hex[:12]}"


def now_ts() -> float:
    return time.time()


class BatchStatus(str, enum.Enum):
    DRAFT = "DRAFT"
    CHECKED = "CHECKED"
    RUNNING = "RUNNING"
    COMPLETED = "COMPLETED"
    LAB_PARTIAL = "LAB_PARTIAL"
    LAB_COMPLETE = "LAB_COMPLETE"
    RELEASED = "RELEASED"
    REJECTED = "REJECTED"
    HOLD = "HOLD"


class StageKind(str, enum.Enum):
    PUMP_DOWN = "PUMP_DOWN"
    HEAT_UP = "HEAT_UP"
    GLOW_CLEAN = "GLOW_CLEAN"
    NITRIDING = "NITRIDING"
    DIFFUSION = "DIFFUSION"
    COOLING = "COOLING"


class ArcKind(str, enum.Enum):
    MICRO_ARC = "MICRO_ARC"
    HARD_ARC = "HARD_ARC"


class AnomalyKind(str, enum.Enum):
    GAS_CHANNEL_SWAP = "GAS_CHANNEL_SWAP"
    GLOW_OVEREXPOSED = "GLOW_OVEREXPOSED"
    TC_PLASMA_INTERFERENCE = "TC_PLASMA_INTERFERENCE"
    FREQUENT_MICRO_ARCS = "FREQUENT_MICRO_ARCS"
    WITNESS_MISSING = "WITNESS_MISSING"


class AnomalyStatus(str, enum.Enum):
    OPEN = "OPEN"
    ACKNOWLEDGED = "ACKNOWLEDGED"
    DISPOSITIONED = "DISPOSITIONED"


class ReleaseDecision(str, enum.Enum):
    RELEASED = "RELEASED"
    REJECTED = "REJECTED"
    HOLD = "HOLD"


ALLOWED_TRANSITIONS: dict[BatchStatus, set[BatchStatus]] = {
    BatchStatus.DRAFT: {BatchStatus.CHECKED},
    BatchStatus.CHECKED: {BatchStatus.RUNNING, BatchStatus.DRAFT},
    BatchStatus.RUNNING: {BatchStatus.COMPLETED},
    BatchStatus.COMPLETED: {BatchStatus.LAB_PARTIAL, BatchStatus.LAB_COMPLETE},
    BatchStatus.LAB_PARTIAL: {BatchStatus.LAB_COMPLETE},
    BatchStatus.LAB_COMPLETE: {
        BatchStatus.RELEASED,
        BatchStatus.REJECTED,
        BatchStatus.HOLD,
    },
    BatchStatus.HOLD: {
        BatchStatus.RELEASED,
        BatchStatus.REJECTED,
        BatchStatus.LAB_COMPLETE,
    },
    BatchStatus.RELEASED: set(),
    BatchStatus.REJECTED: set(),
}
