import logging
import os
import threading

from flask import Flask, jsonify, request
from enrich import enrich

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger(__name__)

app = Flask(__name__)

@app.route("/mutate", methods=["POST"])
def mutate():
    response = request.get_json()
    thread = threading.Thread(target=enrich, args=(response,))
    thread.daemon = True
    thread.start()
    return jsonify({"status": "ok"})
    

@app.route("/healthz", methods=["GET"])
def healthz():
    return jsonify({"status": "ok"})


if __name__ == "__main__":
    tls_cert = os.environ.get("TLS_CERT_FILE", "/tls/tls.crt")
    tls_key = os.environ.get("TLS_KEY_FILE", "/tls/tls.key")

    app.run(
        host="0.0.0.0",
        port=int(os.environ.get("PORT", 8443)),
        ssl_context=(tls_cert, tls_key),
    )

