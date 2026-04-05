# K8S-DETECTION-PIPELINE

A Kubernetes-native security detection pipeline that collects, enriches, and ships
runtime security events from Falco, Tetragon, and workload logs to Elasticsearch via Kafka.

---

## Architecture

### Pipeline 1 — Runtime Event Collection (Fluent Bit)

```
┌─────────────────────────────────────────────────────────────────────┐
│                        EKS Cluster                                  │
│                                                                     │
│  ┌─────────────────┐   ┌──────────────────┐   ┌──────────────────┐  │
│  │ Pod Security    │   │     Falco        │   │    Tetragon      │  │
│  │ Annotator       │   │  (DaemonSet)     │   │  (DaemonSet)     │  │
│  │                 │   │                  │   │                  │  │
│  │ Watches pods    │   │ syscall + K8s    │   │ eBPF process     │  │
│  │ Patches security│   │ audit events     │   │ tracing          │  │
│  │ annotations     │   │ → stdout (JSON)  │   │ → stdout (JSON)  │  │
│  └────────┬────────┘   └────────┬─────────┘   └────────┬─────────┘  │
│           │ security.k8s.io/*   │                      │            │
│           │                     ▼                      ▼            │
│           │          ┌──────────────────────────────────────────┐   │
│           └─────────►│           Fluent Bit (DaemonSet)         │   │
│                      │                                          │   │
│                      │  INPUT:  tail /var/log/containers/*.log  │   │
│                      │  FILTER: kubernetes (metadata + annots)  │   │
│                      │  FILTER: record_modifier (source_type)   │   │
│                      │  OUTPUT: Kafka                           │   │
│                      └────────────────────┬─────────────────────┘   │
└───────────────────────────────────────────│─────────────────────────┘
                                            │
                                            ▼
                               ┌────────────────────────┐
                               │        AWS MSK         │
                               │                        │
                               │      siem-falco        │
                               │      siem-tetragon     │
                               │      siem-k8s          │
                               └───────────┬────────────┘
                                           │
                                           ▼
                               ┌────────────────────────┐
                               │        Logstash        │
                               │                        │
                               │  0200_filter_falco     │
                               │  0201_filter_tetragon  │
                               │  0202_filter_k8s       │
                               └───────────┬────────────┘
                                           │
                                           ▼
                               ┌────────────────────────┐
                               │     Elasticsearch      │
                               │                        │
                               │   logs-falco-siem      │
                               │   logs-tetragon-siem   │
                               │   logs-kubernetes-siem │
                               └────────────────────────┘
```

### Pipeline 2 — K8s Audit Log Collection (CloudWatch → Lambda)

```
┌─────────────────────────────────────────────────────────────────────┐
│                        EKS Cluster                                  │
│                                                                     │
│   kube-apiserver ──► CloudWatch Logs (/aws/eks/<cluster>/cluster)   │
│                                                                     │
└─────────────────────────────┬───────────────────────────────────────┘
                              │ Subscription Filter (push-based)
                              ▼
                 ┌────────────────────────┐
                 │        Lambda          │
                 │  cloudwatch-to-kafka   │
                 │                        │
                 │  - IRSA (no static     │
                 │    credentials)        │
                 │  - VPC-attached        │
                 │  - injects source_type │
                 └───────────┬────────────┘
                             │
                             ▼
                 ┌────────────────────────┐
                 │        AWS MSK         │
                 │                        │
                 │    siem-k8s-audit      │
                 └───────────┬────────────┘
                             │
                             ▼
                 ┌────────────────────────┐
                 │        Logstash        │
                 │                        │
                 │  0203_filter_k8s_audit │
                 └───────────┬────────────┘
                             │
                             ▼
                 ┌────────────────────────┐
                 │     Elasticsearch      │
                 │                        │
                 │  logs-kubernetes-siem  │
                 └────────────────────────┘
```

---

## Components

### Pod Security Annotator
A Python controller that watches all pods and patches `security.k8s.io/*` annotations
based on the pod spec. This enables Fluent Bit to include security context in every log event.

**Annotations added:**

| Annotation | Description |
|---|---|
| `security.k8s.io/privileged` | Whether any container runs as privileged |
| `security.k8s.io/host-pid` | hostPID enabled |
| `security.k8s.io/host-network` | hostNetwork enabled |
| `security.k8s.io/host-ipc` | hostIPC enabled |
| `security.k8s.io/host-path` | hostPath volumes present |
| `security.k8s.io/host-path-mounts` | hostPath mount paths |
| `security.k8s.io/host-path-sensitive` | Sensitive paths (/etc, /proc, etc.) |
| `security.k8s.io/capabilities-added` | Added Linux capabilities |
| `security.k8s.io/allow-privilege-escalation` | allowPrivilegeEscalation |
| `security.k8s.io/run-as-non-root` | runAsNonRoot |
| `security.k8s.io/run-as-user` | runAsUser |
| `security.k8s.io/automount-sa-token` | automountServiceAccountToken |
| `security.k8s.io/network-policy-applied` | NetworkPolicy covers this pod |
| `security.k8s.io/service-account` | ServiceAccount name |
| `security.k8s.io/container-ports` | Declared container ports |
| `security.k8s.io/image-tag-latest` | Uses :latest tag |
| `security.k8s.io/image-pull-policy` | Image pull policy |

### Fluent Bit
DaemonSet that collects container logs from every node.

- **Input**: `tail` on `/var/log/containers/*.log` — separate inputs for Falco, Tetragon, and workload logs
- **Filter**: `kubernetes` — enriches with pod labels, annotations (including security.k8s.io/*), namespace, node info
- **Filter**: `record_modifier` — adds `cluster_name` and `source_type`
- **Output**: Kafka (MSK, unauthenticated on internal network)

### K8s Audit Log Pipeline

EKS API server audit logs are collected via CloudWatch Logs and forwarded to Kafka
using a Lambda function, then normalized to ECS by Logstash.

**Collection flow:**
```
kube-apiserver
    → CloudWatch Logs (/aws/eks/<cluster>/cluster)
    → Lambda (Subscription Filter, push-based, real-time)
    → MSK Kafka (siem-k8s-audit)
    → Logstash (0203_filter_k8s_audit.conf)
    → Elasticsearch (siem-k8s-audit)
```

**Infrastructure:**
- Lambda runs inside VPC with IRSA — no static credentials
- CloudWatch Subscription Filter triggers Lambda in real-time (no polling)
- Deployed and managed via Terraform

**ECS Field Mapping:**

| ECS Field | Source Field |
|---|---|
| `event.action` | `verb` |
| `event.outcome` | `responseStatus.code` (2xx → success, 4xx → failure) |
| `user.name` | `user.username` |
| `source.ip` | `sourceIPs` |
| `url.path` | `requestURI` |
| `kubernetes.audit.objectRef.resource` | `objectRef.resource` |
| `kubernetes.audit.objectRef.subresource` | `objectRef.subresource` |
| `kubernetes.audit.objectRef.namespace` | `objectRef.namespace` |
| `kubernetes.audit.responseStatus.code` | `responseStatus.code` |
| `kubernetes.audit.authorization.decision` | `annotations.authorization.k8s.io/decision` |
| `kubernetes.audit.authorization.reason` | `annotations.authorization.k8s.io/reason` |

### Logstash Pipeline

| File | Role |
|---|---|
| `0000_input.conf` | Kafka consumer for all siem-* topics |
| `0200_filter_falco.conf` | ECS mapping for Falco alerts — maps to `rule.*`, `process.*`, `event.kind: alert` |
| `0201_filter_tetragon.conf` | ECS mapping for Tetragon events — maps to `process.*`, event type routing |
| `0202_filter_k8s.conf` | ECS mapping for K8s workload logs — promotes `security.k8s.io/*` to `kubernetes.security.*` |
| `0203_filter_k8s_audit.conf` | ECS mapping for K8s Audit Log — maps to `event.action`, `user.name`, `kubernetes.audit.*` |
| `9999_output.conf` | Routes to Elasticsearch Data Streams or regular indices |

### ECS Field Mapping

All events are mapped to [Elastic Common Schema (ECS) 8.x](https://www.elastic.co/guide/en/ecs/current/index.html):

```
host.name                    ← kubernetes.host
container.name               ← kubernetes.container_name
container.image.name         ← kubernetes.container_image
container.id                 ← kubernetes.docker_id
orchestrator.cluster.name    ← cluster_name
orchestrator.namespace       ← kubernetes.namespace_name
orchestrator.resource.name   ← kubernetes.pod_name
orchestrator.resource.ip     ← kubernetes.pod_ip
orchestrator.type            → "kubernetes"
kubernetes.security.*        ← security.k8s.io/* annotations
```

---

## Elasticsearch Data Streams

| Data Stream | Source | ILM |
|---|---|---|
| `logs-falco-siem` | Falco alerts | siem policy |
| `logs-tetragon-siem` | Tetragon process events | siem policy |
| `logs-kubernetes-siem` | K8s workload logs | siem policy |
| `siem-k8s-audit` | K8s API server audit logs | siem policy |

---

## Directory Structure

```
K8S-DETECTION-PIPELINE/
├── falco/
│   └── values.yaml                  # Helm values (json_output: true)
├── fluent-bit/
│   ├── configmap.yaml               # Pipeline config (inputs/filters/outputs)
│   ├── daemonset.yaml               # DaemonSet + env vars
│   └── rbac.yaml                    # ServiceAccount + ClusterRole
├── pod-security-annotator/
│   ├── pod_security_annotator.py    # Python watch controller
│   ├── requirements.txt
│   ├── Dockerfile
│   └── k8s/
│       └── manifests.yaml           # RBAC + Deployment
├── lambda/
│   └── cloudwatch_to_kafka/
│       ├── main.py                  # CloudWatch → Kafka forwarder
│       ├── requirements.txt
│       └── builder.sh               # Lambda layer build script
└── logstash/
    └── pipeline/
        ├── 0000_input.conf
        ├── 0200_filter_falco.conf
        ├── 0201_filter_tetragon.conf
        ├── 0202_filter_k8s.conf
        ├── 0203_filter_k8s_audit.conf
        └── 9999_output.conf
```

---

## Detection Use Cases

With security annotations enriched in every log event, the following queries become trivial in Kibana/Elastic SIEM:

```
# Privileged pod executed a shell
kubernetes.security.privileged: true AND rule.name: *shell*

# Process exec in a pod without NetworkPolicy
kubernetes.security.network_policy_applied: false AND event.module: tetragon

# Falco alert from a pod with sensitive host mounts
kubernetes.security.host_path_sensitive: true AND event.module: falco

# SA token auto-mounted + running as root
kubernetes.security.automount_sa_token: true AND
kubernetes.security.run_as_non_root: false AND
event.module: falco

# Secret enumeration via kubectl
kubernetes.audit.objectRef.resource: secrets AND
event.action: (get OR list) AND
event.outcome: success

# Pod exec (kubectl exec)
kubernetes.audit.objectRef.resource: pods AND
kubernetes.audit.objectRef.subresource: exec

# ClusterRoleBinding created
event.action: create AND
kubernetes.audit.objectRef.resource: clusterrolebindings
```

---

## License

Copyright 2026 jaypark81
Licensed under the Apache License, Version 2.0.
See LICENSE for details.
