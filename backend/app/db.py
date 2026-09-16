"""车间记录元数据存储 (SQLite, stdlib)。

批次登记/清单/实验室结果/异常/放行记录存这里; 时序数据在 Influx。
Flutter 端用 Drift 做同样的本地缓存(见 flutter_app)。
"""
from __future__ import annotations

import json
import sqlite3
import threading

from .models import AnomalyKind, AnomalyStatus, BatchStatus, ReleaseDecision, new_id, now_ts

SCHEMA = """
CREATE TABLE IF NOT EXISTS procedures (
  procedure_id TEXT NOT NULL,
  revision TEXT NOT NULL,
  payload TEXT NOT NULL,          -- JSON: ProcedureIn
  approved_by TEXT NOT NULL,
  created_ts REAL NOT NULL,
  PRIMARY KEY (procedure_id, revision)
);
CREATE TABLE IF NOT EXISTS batches (
  batch_id TEXT PRIMARY KEY,
  furnace_id TEXT NOT NULL,
  operator TEXT NOT NULL,
  procedure_id TEXT NOT NULL,
  procedure_revision TEXT NOT NULL,
  status TEXT NOT NULL,
  payload TEXT NOT NULL,          -- JSON: parts/witness/checklist
  created_ts REAL NOT NULL,
  started_ts REAL,
  completed_ts REAL
);
CREATE TABLE IF NOT EXISTS lab_results (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  batch_id TEXT NOT NULL,
  sample_no TEXT NOT NULL,
  payload TEXT NOT NULL,          -- JSON: LabResultIn
  created_ts REAL NOT NULL,
  UNIQUE (batch_id, sample_no)
);
CREATE TABLE IF NOT EXISTS anomalies (
  anomaly_id TEXT PRIMARY KEY,
  batch_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  status TEXT NOT NULL,
  detail TEXT NOT NULL,
  stage_seq INTEGER,
  disposition TEXT,
  created_ts REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS releases (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  batch_id TEXT NOT NULL,
  engineer TEXT NOT NULL,
  decision TEXT NOT NULL,
  comment TEXT NOT NULL,
  created_ts REAL NOT NULL
);
"""


class MetadataStore:
    def __init__(self, path: str | None = None):
        self._conn = sqlite3.connect(path or ":memory:", check_same_thread=False)
        self._conn.row_factory = sqlite3.Row
        self._lock = threading.RLock()
        with self._lock, self._conn:
            self._conn.executescript(SCHEMA)

    def save_procedure(self, proc: dict) -> None:
        with self._lock, self._conn:
            self._conn.execute(
                "INSERT OR REPLACE INTO procedures VALUES (?,?,?,?,?)",
                (
                    proc["procedure_id"],
                    proc.get("revision", "A"),
                    json.dumps(proc),
                    proc["approved_by"],
                    now_ts(),
                ),
            )

    def get_procedure(self, procedure_id: str) -> dict | None:
        with self._lock, self._conn:
            row = self._conn.execute(
                "SELECT payload FROM procedures WHERE procedure_id=? "
                "ORDER BY created_ts DESC LIMIT 1",
                (procedure_id,),
            ).fetchone()
        return json.loads(row["payload"]) if row else None

    def create_batch(
        self,
        furnace_id: str,
        operator: str,
        procedure_id: str,
        procedure_revision: str,
        payload: dict,
    ) -> str:
        batch_id = new_id("BN")
        with self._lock, self._conn:
            self._conn.execute(
                "INSERT INTO batches VALUES (?,?,?,?,?,?,?,?,?,?)",
                (
                    batch_id,
                    furnace_id,
                    operator,
                    procedure_id,
                    procedure_revision,
                    BatchStatus.DRAFT.value,
                    json.dumps(payload),
                    now_ts(),
                    None,
                    None,
                ),
            )
        return batch_id

    def _row_to_batch(self, row: sqlite3.Row) -> dict:
        payload = json.loads(row["payload"])
        return {
            "batch_id": row["batch_id"],
            "furnace_id": row["furnace_id"],
            "operator": row["operator"],
            "procedure_id": row["procedure_id"],
            "procedure_revision": row["procedure_revision"],
            "status": BatchStatus(row["status"]),
            "parts": payload.get("parts", []),
            "witness_samples": payload.get("witness_samples", []),
            "loaded_witness": payload.get("loaded_witness", []),
            "checklist": payload.get("checklist", {}),
            "created_ts": row["created_ts"],
            "started_ts": row["started_ts"],
            "completed_ts": row["completed_ts"],
        }

    def get_batch(self, batch_id: str) -> dict | None:
        with self._lock, self._conn:
            row = self._conn.execute(
                "SELECT * FROM batches WHERE batch_id=?", (batch_id,)
            ).fetchone()
        return self._row_to_batch(row) if row else None

    def list_batches(self) -> list[dict]:
        with self._lock, self._conn:
            rows = self._conn.execute(
                "SELECT * FROM batches ORDER BY created_ts DESC"
            ).fetchall()
        return [self._row_to_batch(r) for r in rows]

    def update_batch_payload(self, batch_id: str, payload: dict) -> None:
        with self._lock, self._conn:
            self._conn.execute(
                "UPDATE batches SET payload=? WHERE batch_id=?",
                (json.dumps(payload), batch_id),
            )

    def set_status(self, batch_id: str, status: BatchStatus) -> None:
        extra = ""
        if status == BatchStatus.RUNNING:
            extra = ", started_ts=%f" % now_ts()
        elif status == BatchStatus.COMPLETED:
            extra = ", completed_ts=%f" % now_ts()
        with self._lock, self._conn:
            self._conn.execute(
                f"UPDATE batches SET status=?{extra} WHERE batch_id=?",
                (status.value, batch_id),
            )

    def upsert_lab_result(
        self, batch_id: str, sample_no: str, payload: dict
    ) -> None:
        with self._lock, self._conn:
            self._conn.execute(
                "INSERT INTO lab_results (batch_id, sample_no, payload, created_ts) "
                "VALUES (?,?,?,?) ON CONFLICT(batch_id, sample_no) DO UPDATE "
                "SET payload=excluded.payload, created_ts=excluded.created_ts",
                (batch_id, sample_no, json.dumps(payload), now_ts()),
            )

    def lab_results(self, batch_id: str) -> list[dict]:
        with self._lock, self._conn:
            rows = self._conn.execute(
                "SELECT sample_no, payload FROM lab_results WHERE batch_id=?",
                (batch_id,),
            ).fetchall()
        return [json.loads(r["payload"]) for r in rows]

    def add_anomaly(
        self,
        batch_id: str,
        kind: AnomalyKind,
        detail: str,
        stage_seq: int | None = None,
    ) -> str:
        with self._lock, self._conn:
            # 幂等: 同批次/类型/阶段已存在未关闭异常时复用, 阶段检查可重复执行
            row = self._conn.execute(
                "SELECT anomaly_id FROM anomalies WHERE batch_id=? AND kind=? "
                "AND status != ? AND COALESCE(stage_seq, -1) = COALESCE(?, -1) "
                "ORDER BY created_ts DESC LIMIT 1",
                (
                    batch_id,
                    kind.value,
                    AnomalyStatus.DISPOSITIONED.value,
                    stage_seq,
                ),
            ).fetchone()
            if row:
                return row["anomaly_id"]
            anomaly_id = new_id("AN")
            self._conn.execute(
                "INSERT INTO anomalies VALUES (?,?,?,?,?,?,?,?)",
                (
                    anomaly_id,
                    batch_id,
                    kind.value,
                    AnomalyStatus.OPEN.value,
                    detail,
                    stage_seq,
                    None,
                    now_ts(),
                ),
            )
        return anomaly_id

    def anomalies(self, batch_id: str) -> list[dict]:
        with self._lock, self._conn:
            rows = self._conn.execute(
                "SELECT * FROM anomalies WHERE batch_id=? ORDER BY created_ts",
                (batch_id,),
            ).fetchall()
        return [dict(r) for r in rows]

    def open_anomaly_of_kind(
        self, batch_id: str, kind: AnomalyKind
    ) -> dict | None:
        with self._lock, self._conn:
            row = self._conn.execute(
                "SELECT * FROM anomalies WHERE batch_id=? AND kind=? "
                "AND status != ? ORDER BY created_ts DESC LIMIT 1",
                (batch_id, kind.value, AnomalyStatus.DISPOSITIONED.value),
            ).fetchone()
        return dict(row) if row else None

    def disposition_anomaly(
        self, anomaly_id: str, engineer: str, disposition: str
    ) -> bool:
        with self._lock, self._conn:
            cur = self._conn.execute(
                "UPDATE anomalies SET status=?, disposition=? WHERE anomaly_id=?",
                (
                    AnomalyStatus.DISPOSITIONED.value,
                    f"[{engineer}] {disposition}",
                    anomaly_id,
                ),
            )
            return cur.rowcount > 0

    def add_release(
        self,
        batch_id: str,
        engineer: str,
        decision: ReleaseDecision,
        comment: str,
    ) -> None:
        with self._lock, self._conn:
            self._conn.execute(
                "INSERT INTO releases (batch_id, engineer, decision, comment, "
                "created_ts) VALUES (?,?,?,?,?)",
                (batch_id, engineer, decision.value, comment, now_ts()),
            )

    def latest_release(self, batch_id: str) -> dict | None:
        with self._lock, self._conn:
            row = self._conn.execute(
                "SELECT * FROM releases WHERE batch_id=? ORDER BY created_ts "
                "DESC LIMIT 1",
                (batch_id,),
            ).fetchone()
        return dict(row) if row else None
