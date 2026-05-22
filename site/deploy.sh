#!/usr/bin/env bash
# Deploy session-essence-site to k8s — pinned to zaphod node (most memory).
#
# Pattern matches tribunal-site:
#   1. rsync site source to ~/session-essence-site on zaphod (skip node_modules/dist)
#   2. docker build on zaphod
#   3. docker save + ctr import into k8s.io containerd namespace (needs sudo on zaphod)
#   4. kubectl apply manifests via .6
#   5. kubectl rollout restart
#
# Caddy on the mabus.ai host reverse-proxies /essence/* to the ClusterIP printed
# at the end of this script.

set -euo pipefail

REMOTE_USER="zaphod-beeblebox"
REMOTE_HOST="192.168.6.56"
REMOTE_DIR="/home/${REMOTE_USER}/session-essence-site"
IMAGE_NAME="session-essence-site"
NAMESPACE="zaphod"
KCTL_HOST="claude@192.168.1.6"
KCTL='sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> rsync to ${REMOTE_HOST}:${REMOTE_DIR}"
ssh "${REMOTE_USER}@${REMOTE_HOST}" "mkdir -p ${REMOTE_DIR}"
rsync -avz --delete \
  --exclude node_modules --exclude dist --exclude .astro --exclude .git \
  "${SCRIPT_DIR}/" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/"

echo "==> docker build on ${REMOTE_HOST}"
ssh "${REMOTE_USER}@${REMOTE_HOST}" "cd ${REMOTE_DIR} && docker build -t ${IMAGE_NAME}:latest ."

echo "==> import into containerd (k8s.io namespace) — may prompt for sudo password on zaphod"
ssh -t "${REMOTE_USER}@${REMOTE_HOST}" "docker save ${IMAGE_NAME}:latest -o /tmp/${IMAGE_NAME}.tar && sudo ctr -n k8s.io images import /tmp/${IMAGE_NAME}.tar && rm /tmp/${IMAGE_NAME}.tar"

echo "==> ensure namespace exists"
ssh "${KCTL_HOST}" "${KCTL} get ns ${NAMESPACE} >/dev/null 2>&1 || ${KCTL} create ns ${NAMESPACE}"

echo "==> apply k8s manifests"
scp "${SCRIPT_DIR}/k8s/deployment.yaml" "${SCRIPT_DIR}/k8s/service.yaml" "${KCTL_HOST}:/tmp/" >/dev/null
ssh "${KCTL_HOST}" "${KCTL} apply -f /tmp/deployment.yaml -f /tmp/service.yaml"

echo "==> rollout restart"
ssh "${KCTL_HOST}" "${KCTL} -n ${NAMESPACE} rollout restart deployment/${IMAGE_NAME}"
ssh "${KCTL_HOST}" "${KCTL} -n ${NAMESPACE} rollout status deployment/${IMAGE_NAME} --timeout=90s"

echo
echo "==> service info"
ssh "${KCTL_HOST}" "${KCTL} -n ${NAMESPACE} get svc ${IMAGE_NAME}"

CLUSTER_IP=$(ssh "${KCTL_HOST}" "${KCTL} -n ${NAMESPACE} get svc ${IMAGE_NAME} -o jsonpath='{.spec.clusterIP}'")

echo
echo "==> done. ClusterIP: ${CLUSTER_IP}"
echo
echo "Add this to /etc/caddy/Caddyfile on the host that serves mabus.ai:"
echo
echo "    mabus.ai {"
echo "        # ... existing config ..."
echo "        handle /essence* {"
echo "            reverse_proxy ${CLUSTER_IP}:80"
echo "        }"
echo "    }"
echo
echo "Then: sudo systemctl reload caddy"
