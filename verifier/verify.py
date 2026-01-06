from flask import Flask, request, jsonify, make_response
from jwt.algorithms import RSAAlgorithm
from threading import Lock
import base64
import jwt
import requests
import time
import uuid

app = Flask(__name__)

def get_expected_nonce(expiry_seconds=60):
    if not hasattr(get_expected_nonce, "_guid"):
        get_expected_nonce._guid = str(uuid.uuid4())
        get_expected_nonce._expiry = time.time() + expiry_seconds
        get_expected_nonce._lock = Lock()

    with get_expected_nonce._lock:
        now = time.time()
        if now > get_expected_nonce._expiry:
            get_expected_nonce._guid = str(uuid.uuid4())
            get_expected_nonce._expiry = now + expiry_seconds
    
        return get_expected_nonce._guid

def check_nonce(report: dict) -> tuple[bool, str]:
    expected_nonce = get_expected_nonce()
    try:
        actual_nonce = report['x-ms-runtime']['client-payload']['nonce']
    except:
        actual_nonce = ''

    if actual_nonce != '':
        actual_nonce = base64.b64decode(actual_nonce).decode('utf-8')

    if expected_nonce != actual_nonce:
        return [False, expected_nonce]

    return [True, '']

def decode_report(jwt_token: str, iss_url: str) -> dict:
    try:
        jwt_header = jwt.get_unverified_header(jwt_token)

        jwks_url = f'{iss_url}/certs'
        jwks = requests.get(jwks_url).json()
        for jwk in jwks['keys']:
            if jwk['kid'] == jwt_header['kid']:
                public_key = RSAAlgorithm.from_jwk(jwk)
                break

        return jwt.decode(
            jwt_token,
            public_key,
            algorithms=[jwt_header['alg']],
            issuer=iss_url,
            options={"verify_signature": True, "verify_exp": True, "verify_aud": False, "verify_iss": True},
        )
    except:
        return {}

@app.route('/verify', methods=['POST'])
def verify():
    payload = request.data.decode('utf-8').strip()
    report = decode_report(payload, 'https://l2vmmaa.eus.attest.azure.net')
    ok, expected_nonce = check_nonce(report)
    if not ok:
        response = make_response(jsonify({'access': 'denied'}), 400)
        response.headers['X-Attest-Nonce'] = expected_nonce
        return response

    return jsonify({'access': 'granted'})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5555)