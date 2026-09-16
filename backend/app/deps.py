"""应用装配: 元数据存储 + 时序存储(InfluxDB 或内存)。"""
from __future__ import annotations

import os
from dataclasses import dataclass

from .db import MetadataStore
from .influx import MemoryTimeseriesStore, TimeseriesStore
from .services.anomaly_service import AnomalyService
from .services.batch_service import BatchService
from .services.lab_service import LabService
from .services.telemetry_service import TelemetryService


@dataclass
class Container:
    meta: MetadataStore
    ts: TimeseriesStore
    batches: BatchService
    telemetry: TelemetryService
    anomalies: AnomalyService
    lab: LabService


def build_container(db_path: str | None = None) -> Container:
    meta = MetadataStore(db_path if db_path else os.environ.get("NITRIDING_DB", ":memory:"))
    influx_url = os.environ.get("INFLUX_URL")
    if influx_url:
        from .influx import InfluxTimeseriesStore

        ts = InfluxTimeseriesStore(
            url=influx_url,
            token=os.environ["INFLUX_TOKEN"],
            org=os.environ.get("INFLUX_ORG", "nitriding"),
            bucket=os.environ.get("INFLUX_BUCKET", "furnace"),
            arc_bucket=os.environ.get("INFLUX_ARC_BUCKET", "arc-events"),
        )
    else:
        ts = MemoryTimeseriesStore()
    return Container(
        meta=meta,
        ts=ts,
        batches=BatchService(meta),
        telemetry=TelemetryService(ts, meta),
        anomalies=AnomalyService(ts, meta),
        lab=LabService(meta),
    )
