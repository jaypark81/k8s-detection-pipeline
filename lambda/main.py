import base64
import gzip
import json
import logging
import os

from confluent_kafka import Producer

logger = logging.getLogger()
logger.setLevel(logging.INFO)

KAFKA_BOOTSTRAP_SERVERS = os.environ["KAFKA_BOOTSTRAP_SERVERS"]
KAFKA_TOPIC             = os.environ.get("KAFKA_TOPIC", "siem-k8s-audit")


def get_producer() -> Producer:
    return Producer({
        "bootstrap.servers": KAFKA_BOOTSTRAP_SERVERS,
        "client.id":         "lambda-cloudwatch-k8s-audit",
        "acks":              "all",
        "retries":           3,
    })


def delivery_report(err, msg):
    if err:
        logger.error("Kafka delivery failed: %s", err)
    else:
        logger.debug("Delivered to %s [%d]", msg.topic(), msg.partition())


def decode_cloudwatch_event(event: dict) -> list[dict]:
    """Decode CloudWatch Logs event → list of log records."""
    raw     = event["awslogs"]["data"]
    decoded = base64.b64decode(raw)
    payload = json.loads(gzip.decompress(decoded))
    return payload.get("logEvents", [])


def handler(event: dict, context):
    log_events = decode_cloudwatch_event(event)
    if not log_events:
        logger.info("No log events in payload, skipping.")
        return

    producer = get_producer()

    for log_event in log_events:
        try:
            audit_record = json.loads(log_event["message"])
            audit_record["source_type"] = "k8s-audit"

            producer.produce(
                topic    = KAFKA_TOPIC,
                value    = json.dumps(audit_record).encode("utf-8"),
                callback = delivery_report,
            )
        except json.JSONDecodeError:
            logger.warning("Skipping non-JSON log event: %s", log_event.get("message", ""))
        except Exception as e:
            logger.error("Failed to produce message: %s", e)

    producer.flush()
    logger.info("Produced %d events to topic '%s'", len(log_events), KAFKA_TOPIC)
