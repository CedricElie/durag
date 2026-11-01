# ==============================================================================
# Stage 1: Build virtual environment and wheels
# ==============================================================================
FROM python:3.11-slim AS builder

WORKDIR /build

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Create virtualenv
ENV VIRTUAL_ENV=/opt/venv
RUN python -m venv ${VIRTUAL_ENV}
ENV PATH="${VIRTUAL_ENV}/bin:${PATH}"

# Install pip tooling
RUN pip install --no-cache-dir --upgrade pip setuptools wheel

# Copy source and pyproject.toml
COPY pyproject.toml README.md ./
COPY src/ ./src/

# Install application and production dependencies into virtualenv
RUN pip install --no-cache-dir .

# ==============================================================================
# Stage 2: Minimal runtime image
# ==============================================================================
FROM python:3.11-slim AS runtime

LABEL maintainer="durag contributors" \
      org.opencontainers.image.title="durag" \
      org.opencontainers.image.description="Private, long-lived operational knowledge base" \
      org.opencontainers.image.licenses="AGPL-3.0-or-later"

# Create a non-root user and group
ENV USER=durag \
    UID=10001 \
    GID=10001 \
    VIRTUAL_ENV=/opt/venv \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

RUN groupadd -g ${GID} ${USER} && \
    useradd -u ${UID} -g ${GID} -s /bin/bash -m ${USER}

# Copy pre-built virtual environment from builder stage
COPY --from=builder --chown=${USER}:${USER} /opt/venv /opt/venv

ENV PATH="/opt/venv/bin:${PATH}"

WORKDIR /app

# Switch to unprivileged user
USER ${UID}

# Default entrypoint is the durag CLI
ENTRYPOINT ["durag"]
CMD ["info"]
