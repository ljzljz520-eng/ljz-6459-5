"""场景: 全流程放行 / 清单前置 / 层结果超窗拒收。"""


def test_full_happy_path(client, ready_batch):
    b = ready_batch

    r = client.post(f"/api/v1/batches/{b}/start")
    assert r.status_code == 200
    assert r.json()["status"] == "RUNNING"

    from tests.conftest import post_telemetry, finish_and_lab

    post_telemetry(client, b, 3, 12)

    # 局部硬打弧(带位置提示)必须被保留
    r = client.post(
        f"/api/v1/batches/{b}/arcs",
        json={
            "ts": 1_000_050.0,
            "stage_seq": 3,
            "kind": "HARD_ARC",
            "peak_current_a": 85.0,
            "duration_ms": 3.0,
            "location_hint": "上层A1齿顶",
        },
    )
    assert r.status_code == 202
    assert r.json()["preserved"] is True

    r = client.post(
        f"/api/v1/batches/{b}/glow-images",
        json={
            "ts": 1_000_060.0,
            "stage_seq": 3,
            "image_uri": "cam/glow_1000060.png",
            "mean_pixel_value": 128.0,
        },
    )
    assert r.status_code == 202
    assert r.json()["overexposed"] is False

    series = client.get(f"/api/v1/batches/{b}/stages/3/series").json()
    assert len(series) == 12

    arcs = client.get(f"/api/v1/batches/{b}/arcs").json()
    assert len(arcs) == 1
    assert arcs[0]["kind"] == "HARD_ARC"

    finish_and_lab(client, b)
    assert client.get(f"/api/v1/batches/{b}").json()["status"] == "LAB_COMPLETE"

    r = client.post(
        f"/api/v1/batches/{b}/release",
        json={
            "engineer": "process.eng",
            "decision": "RELEASED",
            "comment": "层深硬度合格, 打弧已评估",
        },
    )
    assert r.status_code == 200, r.text
    assert client.get(f"/api/v1/batches/{b}").json()["status"] == "RELEASED"

    corr = client.get(f"/api/v1/batches/{b}/correlation").json()
    nitriding = next(s for s in corr["stages"] if s["stage_seq"] == 3)
    assert nitriding["avg_pressure_pa"] == 300.0
    assert abs(nitriding["avg_gas_ratio"]["N2"] - 0.3) < 1e-6
    assert abs(nitriding["avg_gas_ratio"]["H2"] - 0.7) < 1e-6
    assert nitriding["avg_bias_current_a"] == 30.0
    assert nitriding["avg_workpiece_temp_c"] == 520.0
    assert nitriding["hard_arc_count"] == 1
    assert nitriding["glow_image_uris"] == ["cam/glow_1000060.png"]
    assert {r_["sample_no"] for r_ in corr["lab_results"]} == {"WS-01", "WS-02"}
    assert corr["release"]["decision"] == "RELEASED"


def test_checklist_required_before_start(client):
    proc = {
        "procedure_id": "PN-X",
        "revision": "A",
        "approved_by": "eng",
        "stages": [
            {"seq": 0, "kind": "NITRIDING", "name": "氮化", "duration_s": 100}
        ],
    }
    client.post("/api/v1/procedures", json=proc)
    r = client.post(
        "/api/v1/batches",
        json={
            "furnace_id": "LD-50",
            "operator": "li.na",
            "procedure_id": "PN-X",
            "parts": [
                {
                    "part_no": "P1",
                    "material": "42CrMo",
                    "pretreatment": "调质",
                    "fixture_position": "A1",
                }
            ],
            "witness_samples": [
                {"sample_no": "WS-9", "material": "42CrMo", "fixture_position": "B1"}
            ],
        },
    )
    b = r.json()["batch_id"]
    r = client.post(f"/api/v1/batches/{b}/start")
    assert r.status_code == 409
    assert r.json()["code"] == "BAD_STATE"


def test_release_blocked_when_layer_out_of_spec(client, ready_batch):
    b = ready_batch
    from tests.conftest import post_telemetry

    client.post(f"/api/v1/batches/{b}/start")
    post_telemetry(client, b, 3, 5)
    client.post(f"/api/v1/batches/{b}/complete")
    for no in ("WS-01", "WS-02"):
        r = client.post(
            f"/api/v1/batches/{b}/lab-results",
            json={
                "sample_no": no,
                "metallography": "化合物层偏薄",
                "microhardness_hv": [950.0],
                "compound_layer_um": 4.0,
                "diffusion_layer_mm": 0.18,
            },
        )
        assert r.status_code == 201

    r = client.post(
        f"/api/v1/batches/{b}/release",
        json={"engineer": "process.eng", "decision": "RELEASED", "comment": ""},
    )
    assert r.status_code == 409
    assert r.json()["code"] == "SPEC_FAILURE"

    # 工程师可以判定拒收
    r = client.post(
        f"/api/v1/batches/{b}/release",
        json={
            "engineer": "process.eng",
            "decision": "REJECTED",
            "comment": "层深不足, 报废",
        },
    )
    assert r.status_code == 200
