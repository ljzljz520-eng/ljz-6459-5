"""时序存储: InfluxDB 实现 + 内存实现(开发/测试)。

设计要点:
- 炉体时序(压力/流量/偏压/温度)写入 measurement=furnace_telemetry。
- 打弧事件写入独立 measurement=arc_events, 生产环境对应独立 bucket 且
  retention 为无限(局部打弧必须被保留, 不允许随过期策略清除)。
- 辉光图像只存元数据(URI/过曝标记), 图像本身仅用于人工观察辉光均匀性。
"""
from __future__ import annotations

import threading
from dataclasses import dataclass, field
from typing import Protocol


@dataclass
class Point:
    measurement: str
    tags: dict[str, str]
    fields: dict[str, float | str | bool]
    ts: float


class TimeseriesStore(Protocol):
    def write(self, point: Point) -> None: ...

    def query(
        self, measurement: str, batch_id: str, stage_seq: int | None = None
    ) -> list[Point]: ...


class InfluxTimeseriesStore:
    """生产实现: 通过 influxdb-client 写/查 InfluxDB 2.x。

    arc_events 使用独立 bucket(默认 arc-events, 保留期无限),
    确保局部打弧记录永久保留。
    """

    def __init__(
        self,
        url: str,
        token: str,
        org: str,
        bucket: str = "furnace",
        arc_bucket: str = "arc-events",
    ):
        from influxdb_client import InfluxDBClient, Point as InfluxPoint  # noqa
        from influxdb_client.client.write_api import SYNCHRONOUS
        from influxdb_client.domain.write_precision import WritePrecision  # noqa

        self._client = InfluxDBClient(url=url, token=token, org=org)
        self._write = self._client.write_api(write_options=SYNCHRONOUS)
        self._query = self._client.query_api()
        self._org = org
        self._bucket = bucket
        self._arc_bucket = arc_bucket

    def _bucket_for(self, measurement: str) -> str:
        if measurement == "arc_events":
            return self._arc_bucket
        return self._bucket

    def write(self, point: Point) -> None:
        from influxdb_client import Point as InfluxPoint

        p = InfluxPoint(point.measurement).time(int(point.ts), "s")
        for k, v in point.tags.items():
            p = p.tag(k, v)
        for k, v in point.fields.items():
            p = p.field(k, v)
        self._write.write(
            bucket=self._bucket_for(point.measurement), org=self._org, record=p
        )

    def query(
        self, measurement: str, batch_id: str, stage_seq: int | None = None
    ) -> list[Point]:
        bucket = self._bucket_for(measurement)
        stage_filter = ""
        if stage_seq is not None:
            stage_filter = (
                f'  |> filter(fn: (r) => r["stage_seq"] == "{stage_seq}")\n'
            )
        flux = (
            f'\nfrom(bucket: "{bucket}")\n'
            '  |> range(start: 0)\n'
            f'  |> filter(fn: (r) => r._measurement == "{measurement}")\n'
            f'  |> filter(fn: (r) => r["batch_id"] == "{batch_id}")\n'
            f"{stage_filter}"
            '  |> pivot(rowKey:["_time"], columnKey: ["_field"], valueColumn: "_value")\n'
        )
        out: list[Point] = []
        for table in self._query.query(flux, org=self._org):
            for rec in table.records:
                t = rec.get_time()
                fields = {
                    k: v
                    for k, v in rec.values.items()
                    if not k.startswith("_") and k not in ("batch_id", "stage_seq")
                }
                out.append(
                    Point(
                        measurement,
                        {
                            "batch_id": batch_id,
                            "stage_seq": str(rec.values.get("stage_seq", "")),
                        },
                        fields,
                        t.timestamp() if t else 0.0,
                    )
                )
        return out


@dataclass
class MemoryTimeseriesStore:
    """进程内实现, 接口与 Influx 一致; 打弧事件永不清除。"""

    _points: list[Point] = field(default_factory=list)
    _lock: threading.Lock = field(default_factory=threading.Lock)

    def write(self, point: Point) -> None:
        with self._lock:
            self._points.append(point)

    def query(
        self, measurement: str, batch_id: str, stage_seq: int | None = None
    ) -> list[Point]:
        with self._lock:
            pts = [
                p
                for p in self._points
                if p.measurement == measurement
                and p.tags.get("batch_id") == batch_id
                and (
                    stage_seq is None
                    or p.tags.get("stage_seq") == str(stage_seq)
                )
            ]
        return sorted(pts, key=lambda p: p.ts)


MEAS_TELEMETRY = "furnace_telemetry"
MEAS_ARC = "arc_events"
MEAS_GLOW = "glow_images"
