ARG GPU_BACKEND=cuda
ARG ROCM_VERSION=7.0.2

FROM nvidia/cuda:12.6.3-runtime-ubuntu24.04 AS base-cuda
FROM rocm/dev-ubuntu-24.04:${ROCM_VERSION} AS base-rocm

FROM base-${GPU_BACKEND} AS common
ARG DEBIAN_FRONTEND=noninteractive

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Apptainer ignores ENTRYPOINT, so the venv is activated through PATH.
ENV PIP_NO_CACHE_DIR=1 \
    PYTHONNOUSERSITE=1 \
    PYTHONUNBUFFERED=1 \
    VIRTUAL_ENV=/opt/venv \
    PATH=/opt/venv/bin:${PATH}

RUN apt-get update --quiet && \
    apt-get install --no-install-recommends --yes --quiet \
        build-essential \
        ca-certificates \
        libxext6 \
        libxrender1 \
        procps \
        python3 \
        python3-dev \
        python3-pip \
        python3-venv && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN python3 -m venv /opt/venv

# ---- CUDA: cu126 torch matches the all-cuda12 extra (cuEquivariance kernels, tmol) ----
FROM common AS build-cuda
ARG TORCH_VERSION=2.12.1
ARG RFD4_VERSION=0.0.3
# rfd4-proteina 0.0.3 allows atomworks <4, but 3.1.0 removed the to_cif_string it imports.
ARG ATOMWORKS_VERSION=3.0.4
RUN pip install "torch==${TORCH_VERSION}" --index-url https://download.pytorch.org/whl/cu126 && \
    pip install "rfd4-proteina[all-cuda12]==${RFD4_VERSION}" "atomworks[ml,openbabel]==${ATOMWORKS_VERSION}"

# ---- ROCm (experimental): the plain package has no NVIDIA dependencies and RFD4 falls back to
# torch attention and triangle ops when cuEquivariance is absent. ----
FROM common AS build-rocm
ARG TORCH_VERSION=2.12.1
ARG RFD4_VERSION=0.0.3
ARG ATOMWORKS_VERSION=3.0.4
ARG TORCH_ROCM_INDEX=rocm7.2
ENV DISABLE_CUEQUIVARIANCE=1
RUN pip install "torch==${TORCH_VERSION}" --index-url "https://download.pytorch.org/whl/${TORCH_ROCM_INDEX}" && \
    pip install "rfd4-proteina==${RFD4_VERSION}" "atomworks[ml,openbabel]==${ATOMWORKS_VERSION}"

FROM build-${GPU_BACKEND} AS final
ARG GPU_BACKEND
ENV PROTEINDJ_TOOL=rfd4 \
    PROTEINDJ_GPU_BACKEND=${GPU_BACKEND}

# Fails the build if a dependency replaced torch with the wrong backend.
COPY smoke/ /opt/smoke/
RUN python /opt/smoke/check_torch_backend.py
