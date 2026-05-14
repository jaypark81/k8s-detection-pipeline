from elasticsearch import Elasticsearch
import os

client = Elasticsearch(
    hosts=[os.getenv("ELASTICSEARCH_URL")],
    basic_auth=(os.getenv("ES_USER"),os.getenv("ES_PASSWORD")),
    verify_certs=False
)

alert_queries = [
    {
        "field": "hitchhiker.k8s.pod.containers.container.privileged",
        "value": "true",
        "severity": "CRITICAL",
        "name": "Privileged Container Detected"
    },
    {
        "field": "hitchhiker.k8s.pod.host.path.sensitive",
        "value": "true", 
        "severity": "HIGH",
        "name": "Sensitive hostPath Detected"
    }
]

def run_detections():
    seen = set()
    for query in alert_queries:
        body = {
            "query": {
                "bool": {
                    "must": [
                        {
                            "term": {
                                query["field"]: query["value"]
                            }
                        }
                    ],
                    "filter": {
                        "range": {
                            "@timestamp": {
                                "gte": "now-60m",
                                "lte": "now"
                            }
                        }
                    }
                }
            }
        }

        r = client.search(index='logs-*',body=body)
        for hit in r['hits']['hits']:
            hk = hit['_source'].get('hitchhiker', {}).get('k8s', {}).get('pod', {})
            dedup_key = f"{query['name']}:{hk.get('uid', hk.get('name', 'unknown'))}"
            if dedup_key in seen:
                continue
            seen.add(dedup_key)

            alertPrint=hit['_source']['@timestamp']+"  "+query["name"]+": \n"
            if hk.get('uid'):
                alertPrint = alertPrint+ "\tpod_id: "+ hk['uid']+"\n"

            if hk.get('name'):
                alertPrint = alertPrint+ "\tpod_name: "+ hk['name']+"\n"

            if hk.get('user', {}).get('name'):
                alertPrint = alertPrint+ "\tuser: "+ hk['user']['name']+"\n"

            for item in hk.get('containers', []):
                container = item.get('container', {})
                command = container.get('command')
                args = container.get('args')
                if command or args:
                    alertPrint = alertPrint + f"\tcommand and args: {command} {args}\n"
            print(alertPrint)

if __name__ == "__main__":
    run_detections()
