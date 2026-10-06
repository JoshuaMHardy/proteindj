FROM rocm/dev-ubuntu-24.04:6.4.1

ENV ROCM_RELEASE=6.4.1
ENV ROCM_PATH=/opt/rocm-$ROCM_RELEASE
ENV DEBIAN_FRONTEND=noninteractive
ENV PIP_NO_CACHE_DIR=1
ENV PYTHONUNBUFFERED=1
ENV HF_HOME=/cache

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential git libgl1 python3-venv python3-dev && \
    rm -rf /var/lib/apt/lists/* && apt-get clean

RUN python3 -m venv /opt/venv
ENV VIRTUAL_ENV=/opt/venv
ENV PATH=/opt/venv/bin:$PATH

RUN pip install --upgrade pip setuptools wheel

RUN pip install torch==2.9.1 --index-url https://download.pytorch.org/whl/rocm6.4

RUN git clone https://github.com/JoshuaMHardy/boltzgen.git /boltzgen && \
    cd /boltzgen && \
    git checkout eaf6639 && \
    grep -qE '^\s*"(nvidia-ml-py|cuequivariance)' pyproject.toml && \
    sed -i -E '/^\s*"(nvidia-ml-py|cuequivariance)/d' pyproject.toml && \
    pip install . && \
    python -c "import torch; assert torch.version.hip, 'ROCm torch was clobbered'" && \
    python -c "import boltzgen" && \
    python -m compileall -q /opt/venv/lib && \
    mkdir -p /cache

COPY boltzgen_rocm.dockerfile /opt/docker-recipes/

RUN grep -rn 'use_kernels' /boltzgen/src

LABEL org.opencontainers.image.authors="Sarah Beecroft <sarah.beecroft@csiro.au>" \
      org.opencontainers.image.description="BoltzGen 0.3.2 (eaf6639) on ROCm 6.4.1, Ubuntu 24.04, gfx90a" \
      org.opencontainers.image.name="boltzgen_0.3.2_rocm6.4.1_ubuntu24.04"