from dataclasses import dataclass, field, fields

SENSITIVE_HOST_PATHS = {
    "/",
    "/etc",
    "/proc",
    "/sys",
    "/var/run",
    "/var/run/docker.sock",
    "/var/run/containerd",
    "/run/containerd",
    "/root",
    "/home",
}

@dataclass
class ContainerMetadata:
    name: str = field(default=None, metadata={'key': 'container.name'})
    image: str = field(default=None, metadata={'key': 'container.image'})
    listeningPorts: str = field(default=None, metadata={'key': 'container.ports'})
    env: str = field(default=None, metadata={'key': 'container.env'})
    privileged: str = field(default=None, metadata={'key': 'container.privileged'})
    capabilities_added: str = field(default=None, metadata={'key': 'container.capabilities.added'})
    capabilities_dropped: str = field(default=None, metadata={'key': 'container.capabilities.dropped'})
    allowPrivilegeEscalation: str = field(default=None, metadata={'key': 'container.allowprivilegeescalation'})
    runAsUser: str = field(default=None, metadata={'key': 'container.runAsUsers'})
    runAsNonRoot: str = field(default=None, metadata={'key': 'container.runAsNonRoot'})
    listeningPorts: str = field(default=None, metadata={'key': 'container.listeningPorts'})
    command: str = field(default=None, metadata={'key': 'container.command'})
    args: str = field(default=None, metadata={'key': 'container.args'})

@dataclass
class PodMetadata:
    name: str = field(metadata={'key': 'hitchhiker.k8s.pod.name'})
    namespace: str = field(metadata={'key': 'hitchhiker.k8s.pod.namespace'})
    uid: str = field(metadata={'key': 'hitchhiker.k8s.pod.uid'})
    username: str = field(metadata={'key': 'hitchhiker.k8s.pod.user.name'})
    groups: str = field(metadata={'key': 'hitchhiker.k8s.pod.group.name'})
    dnsPolicy: str = field(metadata={'key': 'hitchhiker.k8s.pod.dnspolicy'})
    dnsConfig: str = field(default=None, metadata={'key': 'hitchhiker.k8s.pod.dnsconfig'})
    serviceAccount: str = field(default=None, metadata={'key': 'hitchhiker.k8s.pod.serviceaccount'})
    fieldManager: str = field(default=None, metadata={'key': 'hitchhiker.k8s.pod.fieldmanager'})
    containers: list = field(default_factory=list, metadata={'key': 'hitchhiker.k8s.pod.containers'})
    hostPid: str = field(default=None, metadata={'key': 'hitchhiker.k8s.pod.host.pid'})
    hostNetwork: str = field(default=None, metadata={'key': 'hitchhiker.k8s.pod.host.network'})
    hostIpc: str = field(default=None, metadata={'key': 'hitchhiker.k8s.pod.host.ipc'})
    hostPathMounts: str = field(default=None, metadata={'key': 'hitchhiker.k8s.pod.host.path.mounts'})
    hostPathsSensitive: str = field(default=None, metadata={'key': 'hitchhiker.k8s.pod.host.path.sensitive'})
    hostPathsExist: str = field(default=None, metadata={'key': 'hitchhiker.k8s.pod.host.path.exist'})
    ownerKind: str = field(default=None, metadata={'key': 'hitchhiker.k8s.pod.owner.kind'})
    ownerName: str = field(default=None, metadata={'key': 'hitchhiker.k8s.pod.owner.name'})

def to_dict(obj):
    result = {}
    for f in fields(obj):
        key = f.metadata.get('key', f.name)
        value = getattr(obj, f.name)
        if isinstance(value, list):
            result[key] = [to_dict(i) for i in value]
        else:
            result[key] = value
    return result
