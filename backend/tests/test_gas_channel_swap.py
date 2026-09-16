"""场景1: 气体流量通道互换 —— N2 设定 300/H2 设定 700, 实测 MFC 接反。"""

from tests.conftest import post_telemetry


def test_gas_channel_swap_detected(client, ready_batch):
    b = ready_batch
    client.post(f"/api/v1/batches/{b}/start")

    # MFC1(映射 N2)实测 700, MFC2(映射 H2)实测 300 -> 接反
    post_telemetry(client, b, 3, 10, flows={"MFC1": 700.0, "MFC2": 300.0})

    r = client.post(f"/api/v1/batches/{b}/stages/3/checks")
    assert r.status_code == 200
    gas = r.json()["gas_channels"]
    assert gas["suspect"] is True
    assert set(gas["swapped"]) == {"N2", "H2"}

    anomalies = client.get(f"/api/v1/batches/{b}/anomalies").json()
    assert any(a["kind"] == "GAS_CHANNEL_SWAP" for a in anomalies)


def test_gas_channels_normal_no_alarm(client, ready_batch):
    b = ready_batch
    client.post(f"/api/v1/batches/{b}/start")
    post_telemetry(client, b, 3, 10, flows={"MFC1": 300.0, "MFC2": 700.0})

    gas = client.post(f"/api/v1/batches/{b}/stages/3/checks").json()["gas_channels"]
    assert gas["suspect"] is False
