from tests.conftest import signup


def test_signup_and_me(client):
    headers, user = signup(client, name="Anima")
    assert user["role"] == "user"
    me = client.get("/me", headers=headers).json()
    assert me["name"] == "Anima"
    assert me["phone"].startswith("+91")


def sign_in(client, phone: str, name: str | None = None) -> dict:
    code = client.post("/auth/otp", json={"phone": phone}).json()["dev_code"]
    body = {"phone": phone, "code": code} | ({} if name is None else {"name": name})
    r = client.post("/auth/verify", json=body)
    assert r.status_code == 200, r.text
    return r.json()["user"]


def test_name_typed_when_signing_in_again_replaces_the_stored_one(client):
    phone = "+919876500005"
    assert sign_in(client, phone, name="Ardhendu")["name"] == "Ardhendu"
    assert sign_in(client, phone, name="  Shivam ")["name"] == "Shivam"  # e.g. on a new phone


def test_signing_in_without_a_name_keeps_the_stored_one(client):
    phone = "+919876500006"
    sign_in(client, phone, name="Anima")
    assert sign_in(client, phone)["name"] == "Anima"
    assert sign_in(client, phone, name="   ")["name"] == "Anima"


def test_wrong_code_rejected_and_attempts_capped(client):
    phone = "+919876500001"
    client.post("/auth/otp", json={"phone": phone})
    for _ in range(5):
        assert client.post("/auth/verify", json={"phone": phone, "code": "000000"}).status_code == 401
    # Even the right code fails once attempts are used up.
    assert client.post("/auth/verify", json={"phone": phone, "code": "123456"}).status_code in (401, 429)


def test_code_is_single_use(client):
    phone = "+919876500002"
    code = client.post("/auth/otp", json={"phone": phone}).json()["dev_code"]
    assert client.post("/auth/verify", json={"phone": phone, "code": code}).status_code == 200
    assert client.post("/auth/verify", json={"phone": phone, "code": code}).status_code == 401


def test_cannot_self_assign_admin(client):
    phone = "+919876500003"
    code = client.post("/auth/otp", json={"phone": phone}).json()["dev_code"]
    r = client.post("/auth/verify", json={"phone": phone, "code": code, "role": "admin"})
    assert r.status_code == 422


def test_ten_digit_numbers_normalised(client):
    code = client.post("/auth/otp", json={"phone": "9876500004"}).json()["dev_code"]
    r = client.post("/auth/verify", json={"phone": "+919876500004", "code": code})
    assert r.status_code == 200
    assert r.json()["user"]["phone"] == "+919876500004"


def test_requires_token(client):
    assert client.get("/me").status_code == 401
    assert client.get("/me", headers={"Authorization": "Bearer nonsense"}).status_code == 401


def test_patch_me_cannot_change_role(client):
    headers, _ = signup(client)
    r = client.patch("/me", json={"language": "hi", "role": "admin"}, headers=headers)
    assert r.status_code == 200
    assert r.json()["language"] == "hi"
    assert r.json()["role"] == "user"
