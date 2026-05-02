import json
import logging
import time
import os
from models import PodMetadata, ContainerMetadata, to_dict, SENSITIVE_HOST_PATHS
from store import r
from kubernetes import client, config

logger = logging.getLogger(__name__)

def enrich(response: dict):
    try:
        req = response['request']
        obj = req['object']
        meta = obj['metadata']
        spec = obj['spec']

        uid = meta.get('uid', '')
        name = meta.get('name', '')
        if not uid:
            pod_template_hash = meta.get('labels', {}).get('pod-template-hash', '')
            namespace = req.get('namespace', '')
            uid,name = _resolve_uid(pod_template_hash, namespace)
            if not uid:
                logger.error("[SKIP] uid resolve failed")
                return
        namespace = req.get('namespace', '')
        username = req['userInfo']['username']
        groups = ','.join(req['userInfo'].get('groups', []))
        fieldManager = req.get('options', {}).get('fieldManager', '')

        owners = meta.get('ownerReferences', [])
        if owners:
            owner = owners[0]
            ownerKind = owner.get('kind', '')
            ownerName = owner.get('name', '')
        else:
            ownerKind = 'Pod'
            ownerName = name

        hostPathsArray = [
            v['hostPath']['path']
            for v in spec.get('volumes', [])
            if 'hostPath' in v
        ]

        metadata = PodMetadata(
            uid=uid,
            name=name,
            namespace=namespace,
            username=username,
            groups=groups,
            fieldManager=fieldManager,
            dnsPolicy=spec.get('dnsPolicy', ''),
            serviceAccount=spec.get('serviceAccountName', ''),
            ownerKind=ownerKind,
            ownerName=ownerName,
            hostPid=str(spec.get('hostPID', False)).lower(),
            hostNetwork=str(spec.get('hostNetwork', False)).lower(),
            hostIpc=str(spec.get('hostIPC', False)).lower(),
            hostPathMounts=','.join(hostPathsArray),
            hostPathsSensitive=str(any(p in SENSITIVE_HOST_PATHS for p in hostPathsArray)).lower(),
            hostPathsExist=str(len(hostPathsArray) > 0).lower(),
        )

        for c in spec.get('containers', []):
            sc = c.get('securityContext', {})
            caps = sc.get('capabilities', {})
            ports = c.get('ports', [])

            container = ContainerMetadata(
                name=c.get('name', ''),
                image=c.get('image', ''),
                command=','.join(c.get('command', [])),
                args=','.join(c.get('args', [])),
                env=','.join(f"{e['name']}={e.get('value','')}" for e in c.get('env', [])),
                privileged=str(sc.get('privileged', False)).lower(),
                allowPrivilegeEscalation=str(sc.get('allowPrivilegeEscalation', False)).lower(),
                runAsUser=str(sc.get('runAsUser', '')).lower(),
                runAsNonRoot=str(sc.get('runAsNonRoot', False)).lower(),
                capabilities_added=','.join(caps.get('add', [])).lower(),
                capabilities_dropped=','.join(caps.get('drop', [])).lower(),
                listeningPorts=','.join(f"{p['containerPort']}/{p.get('protocol','TCP')}" for p in ports),
            )
            metadata.containers.append(container)

        clusterName = os.environ.get('CLUSTER_NAME', 'default')
        r.set(f'hitchhiker-k8s-{uid}', json.dumps(to_dict(metadata)))
        r.set(f'hitchhiker-k8s-{clusterName}/{namespace}/{name}', json.dumps(to_dict(metadata)))
        logger.info(f"enriched {namespace}/{name} uid={uid} owner={ownerKind}/{ownerName}")

    except Exception as e:
        logger.error(f"enrich failed: {e}", exc_info=True)


def _resolve_uid(pod_template_hash: str, namespace: str) -> str:
    config.load_incluster_config()
    v1 = client.CoreV1Api()
    max_retries = 5
    for attempt in range(max_retries):
        pods = v1.list_namespaced_pod(
            namespace=namespace,
            label_selector=f"pod-template-hash={pod_template_hash}"
        )
        if pods.items:
            return pods.items[0].metadata.uid, pods.items[0].metadata.name
        logger.warning(f"[RETRY {attempt+1}] uid not resolved yet")
        time.sleep(1)
    return ''
