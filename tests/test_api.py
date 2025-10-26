import os
import sys
import types
import tempfile
import json

# prepare a fake firebase_admin module before importing main
fake = types.ModuleType('firebase_admin')

class Cred:
    def __init__(self, path):
        self.path = path

fake.credentials = types.SimpleNamespace(Certificate=lambda p: Cred(p))

# fake auth submodule
fake.auth = types.SimpleNamespace(
    verify_id_token=lambda token: {'uid': 'testuser'}
)

fake.initialize_app = lambda cred: object()

sys.modules['firebase_admin'] = fake
sys.modules['firebase_admin.credentials'] = fake.credentials
sys.modules['firebase_admin.auth'] = fake.auth

# disable scheduler in tests and allow create_all
os.environ['DISABLE_SCHEDULER'] = '1'
os.environ['DEV_ALLOW_CREATE_ALL'] = '1'
# ensure FIREBASE_CREDENTIALS points to an existing file (not used by fake initialize_app)
import tempfile
_tf = tempfile.NamedTemporaryFile(delete=False)
_tf.write(b"{}")
_tf.flush()
os.environ['FIREBASE_CREDENTIALS'] = _tf.name
# mark testing so main.py uses a dummy firebase app during lifespan
os.environ['TESTING'] = '1'

import sys
from fastapi.testclient import TestClient

# ensure repo root is on sys.path so `import main` works
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
import main

client = TestClient(main.app, raise_server_exceptions=True)


def test_get_profile_unauthorized():
    # no header -> HTTPBearer returns 403 when missing
    r = client.get('/user/profile/')
    assert r.status_code == 403


def test_get_profile_authorized():
    # pass a fake Bearer token (our fake auth will accept it)
    headers = {'Authorization': 'Bearer faketoken'}
    r = client.get('/user/profile/', headers=headers)
    assert r.status_code == 200
    data = r.json()
    assert data['uid'] == 'testuser'


def test_create_and_get_plan():
    headers = {'Authorization': 'Bearer faketoken'}
    payload = {
        'date': '2030-01-01',
        'start_time': '09:00',
        'end_time': '10:00',
        'title': 'Test Plan',
        'description': 'desc'
    }
    r = client.post('/api/plans', json=payload, headers=headers)
    assert r.status_code == 200
    plan = r.json()
    assert plan['title'] == 'Test Plan'

    # list plans (include the plan date explicitly)
    r2 = client.get('/api/plans?start_date=2030-01-01&end_date=2030-01-01', headers=headers)
    assert r2.status_code == 200
    arr = r2.json()
    assert any(p['id'] == plan['id'] for p in arr)
