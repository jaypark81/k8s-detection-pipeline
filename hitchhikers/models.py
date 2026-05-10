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
    name: str = field(default=None)
    image: str = field(default=None)
    listeningPorts: str = field(default=None)
    env: str = field(default=None)
    privileged: str = field(default=None)
    capabilities_added: str = field(default=None)
    capabilities_dropped: str = field(default=None)
    allowPrivilegeEscalation: str = field(default=None)
    runAsUser: str = field(default=None)
    runAsNonRoot: str = field(default=None)
    command: str = field(default=None)
    args: str = field(default=None)

@dataclass
class PodMetadata:
    name: str = field(default=None)
    namespace: str = field(default=None)
    uid: str = field(default=None)
    username: str = field(default=None)
    groups: str = field(default=None)
    dnsPolicy: str = field(default=None)
    dnsConfig: str = field(default=None)
    serviceAccount: str = field(default=None)
    fieldManager: str = field(default=None)
    containers: list = field(default_factory=list)
    hostPid: str = field(default=None)
    hostNetwork: str = field(default=None)
    hostIpc: str = field(default=None)
    hostPathMounts: str = field(default=None)
    hostPathsSensitive: str = field(default=None)
    hostPathsExist: str = field(default=None)
    ownerKind: str = field(default=None)
    ownerName: str = field(default=None)

def to_dict(obj):
    result = {}
    for f in fields(obj):
        value = getattr(obj, f.name)
        if isinstance(value, list):
            result[f.name] = [{"container": to_dict(i)} for i in value]
        elif hasattr(value, '__dataclass_fields__'):
            result[f.name] = to_dict(value)
        else:
            result[f.name] = value
    return result
