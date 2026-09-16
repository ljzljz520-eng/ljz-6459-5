"""场景5: 见证样漏装 —— 装炉确认拦截; 未装炉的样不得回填实验室结果。"""


def test_missing_witness_blocks_loading(client):
    client.post(
        "/api/v1/procedures",
        json={
            "procedure_id": "PN-X",
            "revision": "A",
            "approved_by": "eng",
            "stages": [
                {"seq": 0, "kind": "NITRIDING", "name": "氮化", "duration_s": 100}
            ],
        },
    )
    r = client.post(
        "/api/v1/batches",
        json={
            "furnace_id": "LD-50",
            "operator": "zhang.wei",
            "procedure_id": "PN-X",
            "parts": [
                {
                    "part_no": "P1",
                    "material": "38CrMoAl",
                    "pretreatment": "调质",
                    "fixture_position": "A1",
                }
            ],
            "witness_samples": [
                {"sample_no": "WS-01", "material": "38CrMoAl", "fixture_position": "B1"},
                {"sample_no": "WS-02", "material": "38CrMoAl", "fixture_position": "B2"},
            ],
        },
    )
    b = r.json()["batch_id"]

    r = client.post(
        f"/api/v1/batches/{b}/loading",
        json={
            "loaded_witness": [
                {"sample_no": "WS-01", "fixture_position": "B1"}
            ]
        },
    )
    assert r.status_code == 409
    assert r.json()["code"] == "WITNESS_MISSING"
    assert "WS-02" in r.json()["detail"]

    anomalies = client.get(f"/api/v1/batches/{b}/anomalies").json()
    assert anomalies[0]["kind"] == "WITNESS_MISSING"

    # 补齐后可继续
    r = client.post(
        f"/api/v1/batches/{b}/loading",
        json={
            "loaded_witness": [
                {"sample_no": "WS-01", "fixture_position": "B1"},
                {"sample_no": "WS-02", "fixture_position": "B2"},
            ]
        },
    )
    assert r.status_code == 200


def test_lab_result_rejected_for_unloaded_sample(client, ready_batch):
    b = ready_batch
    client.post(f"/api/v1/batches/{b}/start")
    client.post(f"/api/v1/batches/{b}/complete")

    r = client.post(
        f"/api/v1/batches/{b}/lab-results",
        json={
            "sample_no": "WS-99",
            "metallography": "x",
            "microhardness_hv": [900.0],
            "compound_layer_um": 10.0,
            "diffusion_layer_mm": 0.3,
        },
    )
    assert r.status_code == 409
    assert r.json()["code"] == "SAMPLE_NOT_LOADED"
