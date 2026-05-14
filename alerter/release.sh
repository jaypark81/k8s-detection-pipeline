# release.sh
#!/usr/bin/env bash
set -euo pipefail

IMAGE="ghcr.io/jaypark81/hitchhiker-alerter"

docker build -t ${IMAGE}:local .
SHA=$(docker images --no-trunc --format='{{.ID}}' ${IMAGE}:local | cut -c8-14)
docker tag ${IMAGE}:local ${IMAGE}:${SHA}
docker push ${IMAGE}:${SHA}
sed -i '' "s/tag:.*/tag: ${SHA}/" ./k8s/values.yaml
git add ./k8s/values.yaml
git commit -m "ci: update hitchhiker-webhook image tag to ${SHA}"
git push
