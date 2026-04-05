# convert_sigma.py
from sigma.collection import SigmaCollection
from sigma.backends.elasticsearch import LuceneBackend
from sigma.processing.pipeline import ProcessingPipeline, ProcessingItem
from sigma.processing.transformations import FieldMappingTransformation

'''
pip install pysigma-backend-elasticsearch   # Lucene / ES / OpenSearch
pip install pysigma-backend-splunk          # Splunk SPL
pip install pysigma-backend-microsoft365defender  # KQL / Sentinel

# Splunk
from sigma.backends.splunk import SplunkBackend
backend = SplunkBackend()

# Microsoft Sentinel (KQL)
from sigma.backends.microsoft365defender import Microsoft365DefenderBackend
backend = Microsoft365DefenderBackend()

# OpenSearch
from sigma.backends.opensearch import OpensearchLuceneBackend
backend = OpensearchLuceneBackend()
'''

pipeline = ProcessingPipeline(
    items=[
        ProcessingItem(
            transformation=FieldMappingTransformation({
                "verb":                  "event.action",
                "user.username":         "user.name",
                "objectRef.resource":    "kubernetes.audit.objectRef.resource",
                "objectRef.subresource": "kubernetes.audit.objectRef.subresource",
                "objectRef.namespace":   "kubernetes.audit.objectRef.namespace",
                "responseStatus.code":   "kubernetes.audit.responseStatus.code",
            })
        )
    ]
)

rules = [
    "secret_enumeration.yaml",
    "pod_exec.yaml",
    "clusterrolebinding_created.yaml",
]

backend = LuceneBackend(processing_pipeline=pipeline)
for rule_file in rules:
    with open(rule_file) as f:
        collection = SigmaCollection.from_yaml(f.read())
    for rule in collection:
        # Print rule title and converted Lucene query
        print(f"# {rule.title}")
        print(backend.convert_rule(rule))
        print()
