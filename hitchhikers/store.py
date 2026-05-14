import os
import logging
from elasticsearch import Elasticsearch

logger = logging.getLogger(__name__)

es = Elasticsearch(
    hosts=[os.getenv('ES_HOST', 'https://siem-es-http.elastic-system.svc:9200')],
    basic_auth=(os.getenv('ES_USER', 'elastic'), os.getenv('ES_PASSWORD', '')),
    verify_certs=False
)

HITCHHIKER_INDEX = 'hitchhikers'
