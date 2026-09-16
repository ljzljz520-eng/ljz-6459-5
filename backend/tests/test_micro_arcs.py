"""场景4: 频繁微弧报警, 事件全部保留; 异常未处置前禁止放行。"""

from tests.conftest import post_telemetry


def _post_arcs(client, b, n, gap_s, stage=3, t0=1_000_000.0):
    for i in range(n):
        r = client.post(
            f"/api/v1/batches/{b}/arcs",
            json={
                "ts": t0 + i * gap_s,
                "stage_seq": stage,
                "kind": "MICRO_ARC",
                "peak_current_a": 45.0,
                "duration_ms": 1.5,
            },
        )
        assert r.status_code == 202


def test_frequent_micro_arcs_alarm_and_preserved(client, ready_batch):
    b = ready_batch
    client.post(f"/api/v1/batches/{b}/start")
    post_telemetry(client, b, 3, 5)

    # 5s 间隔 10 个 -> 60s 滑窗 12 次/min
    _post_arcs(client, b, 10, 5.0)

    res = client.post(f"/api/v1/batches/{b}/stages/3/checks").json()["micro_arcs"]
    assert res["alarm"] is True
    assert res["peak_rate_per_min"] > 6.0

    anomalies = client.get(f"/api/v1/batches/{b}/anomalies").json()
    assert any(a["kind"] == "FREQUENT_MICRO_ARCS" for a in anomalies)

    # 局部打弧必须被保留
    arcs = client.get(f"/api/v1/batches/{b}/arcs").json()
    assert len(arcs) == 10
    assert all(a["kind"] == "MICRO_ARC" for a in arcs)


def test_sparse_micro_arcs_no_alarm(client, ready_batch):
    b = ready_batch
    client.post(f"/api/v1/batches/{b}/start")
    post_telemetry(client, b, 3, 5)
    _post_arcs(client, b, 3, 120.0)  # 每 2min 一个, 不报警

    res = client.post(f"/api/v1/batches/{b}/stages/3/checks").json()["micro_arcs"]
    assert res["alarm"] is False


def test_release_blocked_until_arc_anomaly_dispositioned(client, ready_batch):
    b = ready_batch
    client.post(f"/api/v1/batches/{b}/start")
    post_telemetry(client, b, 3, 5)
    _post_arcs(client, b, 8, 5.0)
    client.post(f"/api/v1/batches/{b}/stages/3/checks")

    from tests.conftest import finish_and_lab

    finish_and_lab(client, b)

    r = client.post(
        f"/api/v1/batches/{b}/release",
        json={"engineer": "process.eng", "decision": "RELEASED", "comment": ""},
    )
    assert r.status_code == 409
    assert r.json()["code"] == "ANOMALY_OPEN"

    # 工艺工程师处置全部异常后放行
    anomalies = client.get(f"/api/v1/batches/{b}/anomalies").json()
    for a in anomalies:
        client.post(
            f"/api/v1/anomalies/{a['anomaly_id']}/disposition",
            json={
                "engineer": "process.eng",
                "disposition": "微弧源于装夹尖角, 已评估不影响层质量",
            },
        )

    r = client.post(
        f"/api/v1/batches/{b}/release",
        json={
            "engineer": "process.eng",
            "decision": "RELEASED",
            "comment": "异常已处置",
        },
    )
    assert r.status_code == 200

    corr = client.get(f"/api/v1/batches/{b}/correlation").json()
    nitriding = next(s for s in corr["stages"] if s["stage_seq"] == 3)
    assert nitriding["micro_arc_count"] == 8
