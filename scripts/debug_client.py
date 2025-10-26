import sys, types, os
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
# create fake firebase_admin as in tests
fake = types.ModuleType('firebase_admin')
class Cred:
    def __init__(self, path):
        self.path = path
fake.credentials = types.SimpleNamespace(Certificate=lambda p: Cred(p))
fake.auth = types.SimpleNamespace(verify_id_token=lambda token: {'uid': 'testuser'})
fake.initialize_app = lambda cred: object()
import sys
sys.modules['firebase_admin'] = fake
sys.modules['firebase_admin.credentials'] = fake.credentials
sys.modules['firebase_admin.auth'] = fake.auth
os.environ['DISABLE_SCHEDULER'] = '1'
os.environ['DEV_ALLOW_CREATE_ALL'] = '1'
os.environ['FIREBASE_CREDENTIALS'] = '/tmp/fake-firebase.json'

from fastapi.testclient import TestClient
import main
client = TestClient(main.app)

try:
    r = client.get('/user/profile/', headers={'Authorization': 'Bearer faketoken'})
    print('status', r.status_code)
    print(r.text)
except Exception as e:
    import traceback
    traceback.print_exc()
    print('EXC', e)
