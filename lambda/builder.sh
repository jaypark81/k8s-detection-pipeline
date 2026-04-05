#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAYER_DIR="${SCRIPT_DIR}/layer/python"
OUTPUT="${SCRIPT_DIR}/../cloudwatch_to_kafka_layer.zip"

echo "Building confluent-kafka Lambda layer..."

rm -rf "${SCRIPT_DIR}/layer"
mkdir -p "${LAYER_DIR}"

export PYENV_ROOT="${HOME}/.pyenv"
export PATH="${PYENV_ROOT}/bin:${PATH}"
eval "$(pyenv init -)"
pyenv local 3.12

pip install confluent-kafka==2.3.0 \
  --platform manylinux2014_x86_64 \
  --target "${LAYER_DIR}" \
  --implementation cp \
  --python-version 3.12 \
  --only-binary=:all:

cd "${SCRIPT_DIR}/layer"
zip -r "${OUTPUT}" python/

echo "Layer built: ${OUTPUT}"
