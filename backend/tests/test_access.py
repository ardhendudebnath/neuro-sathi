from tests.conftest import link, signup


def _add_memory(client, headers, user_id, **fields):
    body = {"title": "Rina", "person_name": "Rina", "relationship": "granddaughter"} | fields
    r = client.post(f"/users/{user_id}/memory-book", json=body, headers=headers)
    assert r.status_code == 201, r.text
    return r.json()


def test_unlinked_caregiver_sees_nothing(client):
    user_h, user = signup(client)
    carer_h, _ = signup(client, role="caregiver")
    _add_memory(client, user_h, user["id"])
    assert client.get(f"/users/{user['id']}/memory-book", headers=carer_h).status_code == 404
    assert client.get(f"/dashboard/users/{user['id']}/trends", headers=carer_h).status_code == 404
    assert client.post(f"/users/{user['id']}/memory-book", json={"title": "x"}, headers=carer_h).status_code == 404


def test_other_elderly_user_sees_nothing(client):
    a_h, a = signup(client)
    b_h, _ = signup(client)
    _add_memory(client, a_h, a["id"])
    assert client.get(f"/users/{a['id']}/memory-book", headers=b_h).status_code == 404
    assert client.get(f"/users/{a['id']}/reminders", headers=b_h).status_code == 404


def test_linked_caregiver_can_manage_memory_book_and_reminders(client):
    user_h, user = signup(client)
    carer_h, _ = signup(client, role="caregiver")
    link(client, user_h, carer_h)
    entry = _add_memory(client, carer_h, user["id"])
    assert entry["updated_by_role"] == "caregiver"
    r = client.post(
        f"/users/{user['id']}/reminders",
        json={"kind": "medication", "title": "Metformin", "time_of_day": "08:00:00"},
        headers=carer_h,
    )
    assert r.status_code == 201, r.text
    listed = client.get(f"/users/{user['id']}/memory-book", headers=user_h).json()
    assert [e["id"] for e in listed] == [entry["id"]]


def test_ending_link_revokes_access(client):
    user_h, user = signup(client)
    carer_h, _ = signup(client, role="caregiver")
    lk = link(client, user_h, carer_h)
    assert client.get(f"/users/{user['id']}/memory-book", headers=carer_h).status_code == 200
    assert client.delete(f"/links/{lk['id']}", headers=user_h).status_code == 204
    assert client.get(f"/users/{user['id']}/memory-book", headers=carer_h).status_code == 404


def test_link_codes_are_single_use(client):
    user_h, _ = signup(client)
    c1, _ = signup(client, role="caregiver")
    c2, _ = signup(client, role="caregiver")
    code = client.post("/links/code", headers=user_h).json()["code"]
    assert client.post("/links/redeem", json={"code": code}, headers=c1).status_code == 200
    assert client.post("/links/redeem", json={"code": code}, headers=c2).status_code == 404


def test_role_restrictions(client):
    user_h, _ = signup(client)
    carer_h, _ = signup(client, role="caregiver")
    assert client.post("/links/code", headers=carer_h).status_code == 403
    assert client.post("/links/redeem", json={"code": "ABCDEFGH"}, headers=user_h).status_code == 403
    assert client.get("/dashboard/users", headers=user_h).status_code == 403
    assert client.post("/sync", json={"batch_id": "6f1c1f0e-0000-4000-8000-000000000000", "device_id": "x"}, headers=carer_h).status_code == 403
    assert client.put("/admin/games/x1", json={"slug": "x1", "name": "X", "domain": "attention"}, headers=user_h).status_code == 403


def test_dashboard_lists_linked_users_and_audits(client):
    user_h, user = signup(client, name="Anima")
    carer_h, _ = signup(client, role="caregiver")
    link(client, user_h, carer_h, relationship="son")
    rows = client.get("/dashboard/users", headers=carer_h).json()
    assert len(rows) == 1
    assert rows[0]["user"]["name"] == "Anima"
    assert rows[0]["relationship"] == "son"
