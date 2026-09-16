"""炉体时序接入与阶段聚合。

- 时序写入 InfluxDB(生产) / 内存存储(测试)。
- 打弧事件写入独立 measurement, 永久保留, 任何清理/降采样都不得触碰。
- 辉光图像仅存元数据, 仅供人工观察辉光均匀性, 不做自动判定。
"""
from __future__ import annotations

import statistics

from ..db import MetadataStore
from ..influx import MEAS_ARC, MEAS_GLOW, MEAS_TELEMETRY, Point, TimeseriesStore
from ..models import AnomalyKind, ArcKind, now_ts
from ..schemas import ArcEventIn, GlowImageIn, TelemetryPointIn

OVEREXPOSURE_MEAN_PIXEL = 220.0


class TelemetryService:
    def __init__(self, ts: TimeseriesStore, meta: MetadataStore):
        self.ts = ts
        self.meta = meta

    def ingest_telemetry(self, batch_id: str, body: TelemetryPointIn) -> dict:
        fields: dict[str, float] = {}
        if body.pressure_pa is not None:
            fields["pressure_pa"] = body.pressure_pa
        for ch, flow in body.flows_sccm.items():
            fields[f"flow_{ch}"] = flow
        if body.bias_voltage_v is not None:
            fields["bias_voltage_v"] = body.bias_voltage_v
        if body.bias_current_a is not None:
            fields["bias_current_a"] = body.bias_current_a
        if body.workpiece_temp_c is not None:
            fields["workpiece_temp_c"] = body.workpiece_temp_c
        if body.control_temp_c is not None:
            fields["control_temp_c"] = body.control_temp_c
        self.ts.write(
            Point(
                MEAS_TELEMETRY,
                {"batch_id": batch_id, "stage_seq": str(body.stage_seq)},
                fields,
                body.ts if body.ts is not None else now_ts(),
            )
        )
        return {"stored": True}

    def ingest_arc(self, batch_id: str, body: ArcEventIn) -> dict:
        self.ts.write(
            Point(
                MEAS_ARC,
                {
                    "batch_id": batch_id,
                    "stage_seq": str(body.stage_seq),
                    "kind": body.kind.value,
                },
                {
                    "peak_current_a": body.peak_current_a,
                    "duration_ms": body.duration_ms,
                    "location_hint": body.location_hint or "",
                },
                body.ts if body.ts is not None else now_ts(),
            )
        )
        # 局部打弧必须被保留: 返回 preserved 以显式声明事件已进入独立、
        # 无限保留期的存储, 不做任何抑制/去重/降采样。
        return {"stored": True, "preserved": True}

    def ingest_glow_image(self, batch_id: str, body: GlowImageIn) -> dict:
        overexposed = body.mean_pixel_value >= OVEREXPOSURE_MEAN_PIXEL
        self.ts.write(
            Point(
                MEAS_GLOW,
                {"batch_id": batch_id, "stage_seq": str(body.stage_seq)},
                {
                    "image_uri": body.image_uri,
                    "mean_pixel_value": body.mean_pixel_value,
                    "overexposed": overexposed,
                    "note": body.note or "",
                },
                body.ts if body.ts is not None else now_ts(),
            )
        )
        if overexposed:
            self.meta.add_anomaly(
                batch_id,
                AnomalyKind.GLOW_OVEREXPOSED,
                f"辉光图像过曝(平均灰度 {body.mean_pixel_value:.0f} >= "
                f"{OVEREXPOSURE_MEAN_PIXEL:.0f}), 不可用于均匀性人工观察; "
                "批次不因此自动判废",
                stage_seq=body.stage_seq,
            )
        return {"stored": True, "overexposed": overexposed}

    def stage_series(self, batch_id: str, stage_seq: int) -> list[dict]:
        pts = self.ts.query(MEAS_TELEMETRY, batch_id, stage_seq)
        return [{"ts": p.ts, **p.fields} for p in pts]

    def arc_events(
        self, batch_id: str, stage_seq: int | None = None
    ) -> list[dict]:
        pts = self.ts.query(MEAS_ARC, batch_id, stage_seq)
        return [
            {
                "ts": p.ts,
                "kind": p.tags.get("kind"),
                "stage_seq": int(p.tags.get("stage_seq", "0")),
                **p.fields,
            }
            for p in pts
        ]

    def glow_images(
        self, batch_id: str, stage_seq: int | None = None
    ) -> list[dict]:
        pts = self.ts.query(MEAS_GLOW, batch_id, stage_seq)
        return [
            {
                "ts": p.ts,
                "stage_seq": int(p.tags.get("stage_seq", "0")),
                **p.fields,
            }
            for p in pts
        ]

    def stage_summary(
        self, batch_id: str, stage_seq: int, channel_mapping: dict[str, str]
    ) -> dict:
        pts = self.ts.query(MEAS_TELEMETRY, batch_id, stage_seq)
        arcs = self.ts.query(MEAS_ARC, batch_id, stage_seq)
        glows = self.ts.query(MEAS_GLOW, batch_id, stage_seq)

        def avg(key: str) -> float | None:
            vals = [
                float(p.fields[key])
                for p in pts
                if key in p.fields
            ]
            return statistics.fmean(vals) if vals else None

        gas_totals: dict[str, float] = {}
        for p in pts:
            for k, v in p.fields.items():
                if not k.startswith("flow_"):
                    continue
                gas = channel_mapping.get(k[5:], k[5:])
                gas_totals[gas] = gas_totals.get(gas, 0.0) + float(v)
        total = sum(gas_totals.values())
        gas_ratio = (
            {g: v / total for g, v in gas_totals.items()} if total > 0 else None
        )

        micro = sum(
            1
            for a in arcs
            if a.tags.get("kind") == ArcKind.MICRO_ARC.value
        )
        hard = sum(
            1
            for a in arcs
            if a.tags.get("kind") == ArcKind.HARD_ARC.value
        )
        return {
            "stage_seq": stage_seq,
            "avg_pressure_pa": avg("pressure_pa"),
            "avg_gas_ratio": gas_ratio,
            "avg_bias_voltage_v": avg("bias_voltage_v"),
            "avg_bias_current_a": avg("bias_current_a"),
            "avg_workpiece_temp_c": avg("workpiece_temp_c"),
            "micro_arc_count": micro,
            "hard_arc_count": hard,
            "glow_image_uris": [str(g.fields["image_uri"]) for g in glows],
        }
