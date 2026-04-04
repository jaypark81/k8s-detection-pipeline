# Multi-stage build — keeps final image minimal
FROM python:3.12-slim AS builder

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ── Final image ───────────────────────────────────────────────────────────────
FROM python:3.12-slim

WORKDIR /app

# Copy installed packages from builder
COPY --from=builder /install /usr/local

# Copy application
COPY pod_security_annotator.py .

# Run as non-root
RUN useradd -r -u 1000 annotator
USER annotator

CMD ["python", "pod_security_annotator.py"]
