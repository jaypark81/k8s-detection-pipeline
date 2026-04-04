"""
pod_security_annotator.py

Watches all pods across all namespaces and patches security-related
annotations so that ingester's kubernetes filter can include them
in every log event shipped.

Annotation prefix: security.k8s.io/
"""

import logging
import os
import time
from typing import Any

from kubernetes import client, config, watch
from kubernetes.client.exceptions import ApiException

# ── Logging ───────────────────────────────────────────────────────────────────

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)
log = logging.getLogger(__name__)

# ── Constants ─────────────────────────────────────────────────────────────────

ANNOTATION_PREFIX = "security.k8s.io"

# Host paths considered sensitive for extra flagging
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

# Namespaces to skip (system / infrastructure)
SKIP_NAMESPACES = set(
    os.environ.get(
        "SKIP_NAMESPACES",
        "kube-system,kube-public,kube-node-lease",
    ).split(",")
)

# ── Annotation builders ───────────────────────────────────────────────────────
def _csv(values: list[str]) -> str:
    return ",".join(sorted(set(values))) if values else ""


def build_security_annotations(pod: Any) -> dict[str, str]:
    """
    Extracts security-relevant fields from a pod spec and returns
    a flat dict of annotation key → string value.
    """
    spec = pod.spec
    annotations: dict[str, str] = {}

    # ── Host Access ───────────────────────────────────────────────────────────
    annotations[f"{ANNOTATION_PREFIX}/host-pid"] = str(
        bool(spec.host_pid)
    ).lower()
    annotations[f"{ANNOTATION_PREFIX}/host-network"] = str(
        bool(spec.host_network)
    ).lower()
    annotations[f"{ANNOTATION_PREFIX}/host-ipc"] = str(
        bool(spec.host_ipc)
    ).lower()

    # ── Volume / Host Path ────────────────────────────────────────────────────
    host_paths = [
        v.host_path.path
        for v in (spec.volumes or [])
        if v.host_path is not None
    ]
    annotations[f"{ANNOTATION_PREFIX}/host-path"] = str(
        bool(host_paths)
    ).lower()

    if host_paths:
        annotations[f"{ANNOTATION_PREFIX}/host-path-mounts"] = _csv(host_paths)
        sensitive = any(
            p in SENSITIVE_HOST_PATHS or p.startswith("/proc")
            for p in host_paths
        )
        annotations[f"{ANNOTATION_PREFIX}/host-path-sensitive"] = str(
            sensitive
        ).lower()
    else:
        annotations[f"{ANNOTATION_PREFIX}/host-path-mounts"] = ""
        annotations[f"{ANNOTATION_PREFIX}/host-path-sensitive"] = "false"

    # ── Container-level security ──────────────────────────────────────────────
    privileged_containers: list[str] = []
    priv_esc_containers: list[str] = []
    capabilities_added: list[str] = []
    run_as_users: list[str] = []
    run_as_non_root_values: list[str] = []
    container_ports: list[str] = []
    image_tags_latest: list[str] = []
    pull_policies: list[str] = []

    for c in spec.containers or []:
        sc = c.security_context

        if sc:
            if sc.privileged:
                privileged_containers.append(c.name)

            if sc.allow_privilege_escalation is True:
                priv_esc_containers.append(c.name)

            if sc.capabilities and sc.capabilities.add:
                capabilities_added.extend(sc.capabilities.add)

            if sc.run_as_user is not None:
                run_as_users.append(str(sc.run_as_user))

            if sc.run_as_non_root is not None:
                run_as_non_root_values.append(str(sc.run_as_non_root).lower())

        # Container ports
        for p in c.ports or []:
            proto = p.protocol or "TCP"
            container_ports.append(f"{p.container_port}/{proto}")

        # Image tag
        image = c.image or ""
        tag = image.split(":")[-1] if ":" in image else "latest"
        if tag == "latest":
            image_tags_latest.append(c.name)

        if c.image_pull_policy:
            pull_policies.append(c.image_pull_policy)

    annotations[f"{ANNOTATION_PREFIX}/privileged"] = str(
        bool(privileged_containers)
    ).lower()
    annotations[f"{ANNOTATION_PREFIX}/privileged-containers"] = _csv(
        privileged_containers
    )

    annotations[f"{ANNOTATION_PREFIX}/allow-privilege-escalation"] = str(
        bool(priv_esc_containers)
    ).lower()

    annotations[f"{ANNOTATION_PREFIX}/capabilities-added"] = _csv(
        capabilities_added
    )

    annotations[f"{ANNOTATION_PREFIX}/run-as-user"] = _csv(run_as_users)

    annotations[f"{ANNOTATION_PREFIX}/run-as-non-root"] = (
        "true"
        if run_as_non_root_values and all(
            v == "true" for v in run_as_non_root_values
        )
        else "false"
    )

    annotations[f"{ANNOTATION_PREFIX}/container-ports"] = _csv(container_ports)

    annotations[f"{ANNOTATION_PREFIX}/image-tag-latest"] = str(
        bool(image_tags_latest)
    ).lower()

    # Use most restrictive pull policy seen across containers
    annotations[f"{ANNOTATION_PREFIX}/image-pull-policy"] = _csv(pull_policies)

    # ── Identity ──────────────────────────────────────────────────────────────
    sa = spec.service_account_name or "default"
    annotations[f"{ANNOTATION_PREFIX}/service-account"] = sa

    automount = spec.automount_service_account_token
    # K8s default is True when not explicitly set
    annotations[f"{ANNOTATION_PREFIX}/automount-sa-token"] = str(
        automount is not False
    ).lower()

    return annotations


# ── NetworkPolicy check ───────────────────────────────────────────────────────


def has_network_policy(
    networking: client.NetworkingV1Api,
    namespace: str,
    pod_labels: dict[str, str],
) -> bool:
    """
    Returns True if at least one NetworkPolicy in the namespace
    selects this pod via its podSelector.
    """
    try:
        policies = networking.list_namespaced_network_policy(namespace)
    except ApiException as e:
        log.warning("Failed to list NetworkPolicies in %s: %s", namespace, e)
        return False

    for policy in policies.items:
        selector = policy.spec.pod_selector
        match_labels = (
            selector.match_labels if selector and selector.match_labels else {}
        )
        # Empty podSelector matches all pods in namespace
        if not match_labels:
            return True
        # Check if all selector labels are present in pod labels
        if all(pod_labels.get(k) == v for k, v in match_labels.items()):
            return True

    return False


# ── Patch helper ──────────────────────────────────────────────────────────────


def patch_annotations(
    core: client.CoreV1Api,
    namespace: str,
    pod_name: str,
    new_annotations: dict[str, str],
    existing_annotations: dict[str, str],
) -> bool:
    """
    Patches pod annotations only when there is a diff.
    Returns True if a patch was applied.
    """
    # Filter to only our prefix
    current = {
        k: v
        for k, v in (existing_annotations or {}).items()
        if k.startswith(ANNOTATION_PREFIX)
    }

    if current == new_annotations:
        return False

    body = {"metadata": {"annotations": new_annotations}}
    try:
        core.patch_namespaced_pod(pod_name, namespace, body)
        log.info("Patched %s/%s", namespace, pod_name)
        return True
    except ApiException as e:
        if e.status == 404:
            log.debug("Pod %s/%s already gone", namespace, pod_name)
        else:
            log.error(
                "Failed to patch %s/%s: %s", namespace, pod_name, e
            )
        return False


# ── Main watch loop ───────────────────────────────────────────────────────────


def run() -> None:
    # Load in-cluster config when running as a Pod,
    # fall back to local kubeconfig for development
    try:
        config.load_incluster_config()
        log.info("Loaded in-cluster config")
    except config.ConfigException:
        config.load_kube_config()
        log.info("Loaded local kubeconfig")

    core = client.CoreV1Api()
    networking = client.NetworkingV1Api()

    log.info("Starting pod security annotator (skip_namespaces=%s)", SKIP_NAMESPACES)

    while True:
        w = watch.Watch()
        try:
            for event in w.stream( core.list_pod_for_all_namespaces, timeout_seconds=3600, ):
                event_type: str = event["type"]
                pod = event["object"]

                namespace = pod.metadata.namespace
                pod_name = pod.metadata.name

                # Skip system namespaces
                if namespace in SKIP_NAMESPACES:
                    continue

                # Only process running pods
                phase = pod.status.phase if pod.status else None
                if phase not in ("Running", "Pending"):
                    continue

                if event_type not in ("ADDED", "MODIFIED"):
                    continue

                # Build security annotations
                annotations = build_security_annotations(pod)

                # NetworkPolicy check
                pod_labels = pod.metadata.labels or {}
                np_applied = has_network_policy(networking, namespace, pod_labels)
                annotations[f"{ANNOTATION_PREFIX}/network-policy-applied"] = str(
                    np_applied
                ).lower()

                # Patch if changed
                patch_annotations(
                    core,
                    namespace,
                    pod_name,
                    annotations,
                    pod.metadata.annotations or {},
                )

        except ApiException as e:
            log.error("Watch API error: %s — restarting in 10s", e)
            time.sleep(10)
        except Exception as e:
            log.error("Unexpected error: %s — restarting in 10s", e)
            time.sleep(10)
        finally:
            w.stop()


if __name__ == "__main__":
    run()
