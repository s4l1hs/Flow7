import sys, types, os
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
# fake firebase_admin
fake = types.ModuleType('firebase_admin')
class Cred:
    def __init__(self, path):
        self.path = path
fake.credentials = types.SimpleNamespace(Certificate=lambda p: Cred(p))
# fake auth module
fake.auth = types.SimpleNamespace(verify_id_token=lambda token: {'uid': 'testuser'})
fake.initialize_app = lambda cred: object()

sys.modules['firebase_admin'] = fake
sys.modules['firebase_admin.credentials'] = fake.credentials
sys.modules['firebase_admin.auth'] = fake.auth

os.environ['DISABLE_SCHEDULER'] = '1'
os.environ['DEV_ALLOW_CREATE_ALL'] = '1'
import tempfile
_tf = tempfile.NamedTemporaryFile(delete=False)
_tf.write(b"{}")
_tf.flush()
os.environ['FIREBASE_CREDENTIALS'] = _tf.name

import main

print('Before lifespan FIREBASE_APP =', getattr(main, 'FIREBASE_APP', None))

# run lifespan startup manually to see exceptions
try:
    with main.app.router.lifespan_context(main.app):
        print('During lifespan FIREBASE_APP =', main.FIREBASE_APP)
except Exception as e:
    import traceback
    traceback.print_exc()
    print('lifespan raised', e)

print('After lifespan FIREBASE_APP =', getattr(main, 'FIREBASE_APP', None))
