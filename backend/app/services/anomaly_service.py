"""过程异常检测: 通道互换 / 热电偶受等离子体干扰 / 频繁微弧。

辉光过曝在 TelemetryService 入库时判定; 见证样漏装在 BatchService 装炉确认时判定。
"""
from __future__ import annotations

import statistics

from ..db import MetadataStore
from ..influx import MEAS_ARC, MEAS_TELEMETRY, TimeseriesStore
from ..models import AnomalyKind, ArcKind

GAS_RATIO_TOLERANCE = 0.05
TC_PLASMA_DEVIATION_C = 40.0
DEFAULT_MAX_MICRO_ARC_RATE = 6.0
ARC_WINDOW_S = 60.0


class AnomalyService:
    def __init__(self, ts: TimeseriesStore, meta: MetadataStore):
        self.ts = ts
        self.meta = meta

    def check_gas_channels(
        self,
        batch_id: str,
        stage_seq: int,
        gas_setpoints: dict[str, float],
        channel_mapping: dict[str, str],
    ) -> dict:
        pts = self.ts.query(MEAS_TELEMETRY, batch_id, stage_seq)
        measured: dict[str, list[float]] = {}
        for p in pts:
            for k, v in p.fields.items():
                if not k.startswith("flow_"):
                    continue
                gas = channel_mapping.get(k[5:], k[5:])
                measured.setdefault(gas, []).append(float(v))
        measured_avg = {
            g: statistics.fmean(vs) for g, vs in measured.items() if vs
        }
        set_total = sum(gas_setpoints.values())
        mea_total = sum(measured_avg.values())
        if set_total <= 0 or mea_total <= 0:
            return {"suspect": False, "reason": "数据不足"}

        def shares(d: dict[str, float], total: float) -> dict[str, float]:
            return {g: v / total for g, v in d.items()}

        set_share = shares(gas_setpoints, set_total)
        mea_share = shares(measured_avg, mea_total)
        gases = set(set_share) | set(mea_share)
        direct_err = max(
            abs(set_share.get(g, 0.0) - mea_share.get(g, 0.0)) for g in gases
        )
        if direct_err <= GAS_RATIO_TOLERANCE:
            return {"suspect": False, "direct_error": direct_err}

        swapped_with: tuple[str, str] | None = None
        for g_set, sp in set_share.items():
            for g_mea, mp in mea_share.items():
                if g_set != g_mea and abs(sp - mp) <= GAS_RATIO_TOLERANCE:
                    swapped_with = (g_set, g_mea)
                    break
            if swapped_with:
                break

        if swapped_with:
            detail = (
                f"疑似气体通道互换: {swapped_with[0]} 设定比例 "
                f"{set_share[swapped_with[0]]:.2f} 出现在 "
                f"{swapped_with[1]} 通道实测中, 直接偏差 "
                f"{direct_err:.2f} > {GAS_RATIO_TOLERANCE:.2f}"
            )
            self.meta.add_anomaly(
                batch_id,
                AnomalyKind.GAS_CHANNEL_SWAP,
                detail,
                stage_seq=stage_seq,
            )
            return {
                "suspect": True,
                "swapped": swapped_with,
                "direct_error": direct_err,
            }
        return {
            "suspect": False,
            "direct_error": direct_err,
            "reason": "比例超差但非通道互换模式",
        }

    def check_thermocouple(self, batch_id: str, stage_seq: int) -> dict:
        pts = self.ts.query(MEAS_TELEMETRY, batch_id, stage_seq)
        hits = 0
        checked = 0
        max_dev = 0.0
        for p in pts:
            f = p.fields
            if "workpiece_temp_c" not in f or "control_temp_c" not in f:
                continue
            if float(f.get("bias_voltage_v", 0.0)) > 100.0:
                checked += 1
                dev = abs(float(f["workpiece_temp_c"]) - float(f["control_temp_c"]))
                max_dev = max(max_dev, dev)
                if dev > TC_PLASMA_DEVIATION_C:
                    hits += 1
        if checked and hits / checked >= 0.5:
            detail = (
                f"工件热电偶疑似受等离子体影响: 偏压期间 {hits}/{checked} 点与控温偶"
                f"偏差超过 {TC_PLASMA_DEVIATION_C:.0f}°C (最大 {max_dev:.0f}°C); "
                "该偶读数标记为不可信, 放行以控温偶为准"
            )
            self.meta.add_anomaly(
                batch_id,
                AnomalyKind.TC_PLASMA_INTERFERENCE,
                detail,
                stage_seq=stage_seq,
            )
            return {
                "suspect": True,
                "hits": hits,
                "checked": checked,
                "max_deviation_c": max_dev,
            }
        return {"suspect": False, "hits": hits, "checked": checked}

    def check_micro_arc_rate(
        self,
        batch_id: str,
        stage_seq: int,
        max_rate_per_min: float = DEFAULT_MAX_MICRO_ARC_RATE,
    ) -> dict:
        arcs = [
            p
            for p in self.ts.query(MEAS_ARC, batch_id, stage_seq)
            if p.tags.get("kind") == ArcKind.MICRO_ARC.value
        ]
        if len(arcs) < 2:
            return {"alarm": False, "peak_rate_per_min": float(len(arcs))}
        times = [p.ts for p in arcs]
        peak = 0.0
        for i, t0 in enumerate(times):
            j = i
            while j < len(times) and times[j] - t0 <= ARC_WINDOW_S:
                j += 1
            peak = max(peak, (j - i) * 60.0 / ARC_WINDOW_S)
        if peak > max_rate_per_min:
            detail = (
                f"频繁微弧: 阶段 {stage_seq} 峰值 {peak:.1f} 次/min 超过限值 "
                f"{max_rate_per_min:.1f}; 建议检查装夹与表面清洁, 事件已全部保留"
            )
            self.meta.add_anomaly(
                batch_id,
                AnomalyKind.FREQUENT_MICRO_ARCS,
                detail,
                stage_seq=stage_seq,
            )
            return {"alarm": True, "peak_rate_per_min": peak, "limit": max_rate_per_min}
        return {"alarm": False, "peak_rate_per_min": peak, "limit": max_rate_per_min}
