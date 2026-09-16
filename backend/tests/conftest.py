import pytest
from fastapi.testclient import TestClient

from app.main import create_app

PROCEDURE = {
    "procedure_id": "PN-42CrMo-520",
    "revision": "C",
    "approved_by": "chief.engineer",
    "stages": [
        {"seq": 0, "kind": "PUMP_DOWN", "name": "抽真空", "duration_s": 1800},
        {
            "seq": 1,
            "kind": "HEAT_UP",
            "name": "升温",
            "duration_s": 3600,
            "temp_setpoint_c": 520,
        },
        {
            "seq": 2,
            "kind": "GLOW_CLEAN",
            "name": "辉光清洗",
            "duration_s": 480,
            "temp_setpoint_c": 150,
            "pressure_setpoint_pa": 200,
            "gas_setpoints": {"H2": 50, "Ar": 700},
            "bias_voltage_v": 480,
        },
        {
            "seq": 3,
            "kind": "NITRIDING",
            "name": "氮化",
            "duration_s": 36000,
            "temp_setpoint_c": 520,
            "pressure_setpoint_pa": 300,
            "gas_setpoints": {"N2": 300, "H2": 700},
            "bias_voltage_v": 650,
            "bias_current_limit_a": 40,
            "max_micro_arc_rate_per_min": 6.0,
        },
        {"seq": 4, "kind": "COOLING", "name": "冷却", "duration_s": 7200},
    ],
    "compound_layer_um_min": 8.0,
    "compound_layer_um_max": 20.0,
    "diffusion_layer_mm_min": 0.25,
    "diffusion_layer_mm_max": 0.5,
    "surface_hardness_hv_min": 900.0,
}

BATCH_BODY = {
    "furnace_id": "LD-50",
    "operator": "zhang.wei",
    "procedure_id": "PN-42CrMo-520",
    "parts": [
        {
            "part_no": "GEAR-001",
            "material": "42CrMo",
            "pretreatment": "调质+除油",
            "fixture_position": "上层A1",
        },
        {
            "part_no": "GEAR-002",
            "material": "42CrMo",
            "pretreatment": "调质+除油",
            "fixture_position": "上层A2",
        },
    ],
    "witness_samples": [
        {"sample_no": "WS-01", "material": "42CrMo", "fixture_position": "中层B1"},
        {"sample_no": "WS-02", "material": "42CrMo", "fixture_position": "下层C2"},
    ],
}

CHECKLIST = {
    "gas_line_confirmed": True,
    "insulation_confirmed": True,
    "gas_channel_mapping": {"MFC1": "N2", "MFC2": "H2", "MFC3": "Ar"},
}


@pytest.fixture
def client():
    app = create_app()
    with TestClient(app) as c:
        yield c


@pytest.fixture
def ready_batch(client):
    r = client.post("/api/v1/procedures", json=PROCEDURE)
    assert r.status_code == 201
    r = client.post("/api/v1/batches", json=BATCH_BODY)
    assert r.status_code == 201
    batch_id = r.json()["batch_id"]
    r = client.post(
        f"/api/v1/batches/{batch_id}/loading",
        json={
            "loaded_witness": [
                {"sample_no": "WS-01", "fixture_position": "中层B1"},
                {"sample_no": "WS-02", "fixture_position": "下层C2"},
            ]
        },
    )
    assert r.status_code == 200
    r = client.post(f"/api/v1/batches/{batch_id}/checklist", json=CHECKLIST)
    assert r.status_code == 200
    assert r.json()["status"] == "CHECKED"
    return batch_id


def post_telemetry(
    client,
    batch_id,
    stage_seq,
    n,
    pressure=300.0,
    flows=None,
    bias_v=650.0,
    bias_a=30.0,
    workpiece_c=520.0,
    control_c=520.0,
    t0=1_000_000.0,
):
    if flows is None:
        flows = {"MFC1": 300.0, "MFC2": 700.0}
    for i in range(n):
        r = client.post(
            f"/api/v1/batches/{batch_id}/telemetry",
            json={
                "ts": t0 + i * 10,
                "stage_seq": stage_seq,
                "pressure_pa": pressure,
                "flows_sccm": flows,
                "bias_voltage_v": bias_v,
                "bias_current_a": bias_a,
                "workpiece_temp_c": workpiece_c,
                "control_temp_c": control_c,
            },
        )
        assert r.status_code == 202


def finish_and_lab(client, batch_id):
    assert client.post(f"/api/v1/batches/{batch_id}/complete").status_code == 200
    for no, cl, dl in [("WS-01", 12.0, 0.32), ("WS-02", 11.5, 0.31)]:
        r = client.post(
            f"/api/v1/batches/{batch_id}/lab-results",
            json={
                "sample_no": no,
                "metallography": "化合物层连续, 无疏松",
                "microhardness_hv": [1050.0, 980.0, 820.0, 600.0],
                "compound_layer_um": cl,
                "diffusion_layer_mm": dl,
            },
        )
        assert r.status_code == 201
    return batch_id
