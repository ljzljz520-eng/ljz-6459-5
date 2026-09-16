"""场景3: 工件热电偶在偏压期间受等离子体干扰(与控温偶偏差大)。"""

from tests.conftest import post_telemetry


def test_tc_plasma_interference_detected(client, ready_batch):
    b = ready_batch
    client.post(f"/api/v1/batches/{b}/start")
    # 氮化阶段偏压 650V, 工件偶 600°C vs 控温偶 520°C
    post_telemetry(client, b, 3, 10, bias_v=600.0, workpiece_c=600.0, control_c=520.0)

    tc = client.post(f"/api/v1/batches/{b}/stages/3/checks").json()["thermocouple"]
    assert tc["suspect"] is True
    assert tc["hits"] == 10

    anomalies = client.get(f"/api/v1/batches/{b}/anomalies").json()
    assert any(a["kind"] == "TC_PLASMA_INTERFERENCE" for a in anomalies)


def test_tc_normal_when_bias_off(client, ready_batch):
    b = ready_batch
    client.post(f"/api/v1/batches/{b}/start")
    # 升温阶段无偏压, 即便两偶有差值也不判干扰
    post_telemetry(
        client, b, 1, 10, bias_v=0.0, workpiece_c=480.0, control_c=520.0
    )
    tc = client.post(f"/api/v1/batches/{b}/stages/1/checks").json()["thermocouple"]
    assert tc["suspect"] is False
