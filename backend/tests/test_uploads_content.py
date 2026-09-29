import uuid
from urllib.parse import urlparse

from app.models import Role
from tests.conftest import link, login_again, make_role, signup

PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 64


def test_photo_upload_and_signed_url(client):
    user_h, user = signup(client)
    carer_h, _ = signup(client, role="caregiver")
    link(client, user_h, carer_h)
    r = client.post(f"/users/{user['id']}/memory-book/upload", files={"file": ("p.png", PNG, "image/png")}, headers=carer_h)
    assert r.status_code == 200, r.text
    key = r.json()["photo_key"]
    entry = client.post(f"/users/{user['id']}/memory-book", json={"title": "Wedding", "kind": "memory", "photo_key": key}, headers=carer_h).json()
    url = client.get(f"/users/{user['id']}/memory-book/{entry['id']}/photo", headers=user_h).json()["url"]
    parsed = urlparse(url)
    got = client.get(f"{parsed.path}?{parsed.query}")
    assert got.status_code == 200 and got.content == PNG
    # Tampered signature is refused.
    assert client.get(f"{parsed.path}?{parsed.query[:-4]}beef").status_code == 403


def test_upload_rejects_non_images_and_foreign_keys(client):
    a_h, a = signup(client)
    b_h, b = signup(client)
    r = client.post(f"/users/{a['id']}/memory-book/upload", files={"file": ("x.png", b"<script>", "image/png")}, headers=a_h)
    assert r.status_code == 415
    b_key = client.post(f"/users/{b['id']}/memory-book/upload", files={"file": ("p.png", PNG, "image/png")}, headers=b_h).json()["photo_key"]
    r = client.post(f"/users/{a['id']}/memory-book", json={"title": "x", "photo_key": b_key}, headers=a_h)
    assert r.status_code == 400


def test_content_and_admin(client):
    h, user = signup(client)
    games = client.get("/content/games", headers=h).json()
    assert {g["slug"] for g in games} >= {"photo_recall", "market_list", "my_day"}
    cultural = client.get("/content/cultural?region=assam", headers=h).json()
    titles = {c["title"] for c in cultural}
    assert "Bihu" in titles and "Morning tea" in titles and "Loktak Lake" not in titles
    assert client.get("/content/language-packs/hi", headers=h).json()["strings"]["play"] == "खेलें"

    make_role(user["id"], Role.admin)
    admin_h = login_again(client, user["phone"])
    r = client.put("/admin/games/tea_sort", json={"slug": "tea_sort", "name": "Tea Sorting", "domain": "attention"}, headers=admin_h)
    assert r.status_code == 200, r.text
    assert "tea_sort" in {g["slug"] for g in client.get("/content/games", headers=h).json()}


def test_link_code_redeem_with_unknown_code(client):
    carer_h, _ = signup(client, role="caregiver")
    assert client.post("/links/redeem", json={"code": uuid.uuid4().hex[:8].upper()}, headers=carer_h).status_code == 404
