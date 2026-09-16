"""场景2: 辉光图像过曝。相机图像仅用于人工观察均匀性, 不做自动判废。"""


def test_overexposed_glow_image_flagged(client, ready_batch):
    b = ready_batch
    client.post(f"/api/v1/batches/{b}/start")

    r = client.post(
        f"/api/v1/batches/{b}/glow-images",
        json={
            "ts": 1_000_100.0,
            "stage_seq": 3,
            "image_uri": "cam/glow_sat.png",
            "mean_pixel_value": 245.0,
        },
    )
    assert r.status_code == 202
    assert r.json()["overexposed"] is True

    anomalies = client.get(f"/api/v1/batches/{b}/anomalies").json()
    glow = [a for a in anomalies if a["kind"] == "GLOW_OVEREXPOSED"]
    assert len(glow) == 1
    assert "过曝" in glow[0]["detail"]

    imgs = client.get(f"/api/v1/batches/{b}/glow-images").json()
    assert imgs[0]["overexposed"] is True
    # 图像仅供人工观察: 不自动停批/判废
    assert client.get(f"/api/v1/batches/{b}").json()["status"] == "RUNNING"


def test_normal_glow_image_not_flagged(client, ready_batch):
    b = ready_batch
    client.post(f"/api/v1/batches/{b}/start")
    r = client.post(
        f"/api/v1/batches/{b}/glow-images",
        json={
            "ts": 1_000_100.0,
            "stage_seq": 3,
            "image_uri": "cam/glow_ok.png",
            "mean_pixel_value": 110.0,
        },
    )
    assert r.json()["overexposed"] is False
    assert (
        client.get(f"/api/v1/batches/{b}/anomalies").json() == []
    )
