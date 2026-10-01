ARG GPU_BACKEND=cuda

# ---- Backend-specific base images ----
FROM nvidia/cuda:12.8.0-base-ubuntu24.04 AS base-cuda
FROM quay.io/sarahbeecroft9/rocm-mpich-base:rocm7.2.3-mpich3.4.3-ubuntu24.04 AS base-rocm

# Selects one of the above as the working base for the rest of the build
FROM base-${GPU_BACKEND} AS final
ARG GPU_BACKEND

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

LABEL org.opencontainers.image.authors="JoshuaHardy, DylanSilke, SarahBeecroft" \
      org.opencontainers.image.description="FAMPNN container (${GPU_BACKEND} backend)"

# ---- Shared system deps (identical for both backends) ----
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update --quiet && \
    apt-get install --no-install-recommends --yes --quiet \
        build-essential \
        git \
        wget \
        software-properties-common && \
    rm -rf /var/lib/apt/lists/* && \
    apt-get autoremove --yes && \
    apt-get clean

# ---- Shared Miniforge + Python 3.10 env (identical for both backends) ----
RUN wget -q https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh -O /tmp/miniforge.sh && \
    bash /tmp/miniforge.sh -b -p /opt/conda && rm /tmp/miniforge.sh
ENV PATH="/opt/conda/bin:${PATH}"

RUN mamba install -y -c conda-forge -c bioconda python=3.10 && \
    mamba clean -afy

# ---- Shared application source ----
RUN git clone https://github.com/PapenfussLab/fampnn.git /app/fampnn && \
    git -C /app/fampnn checkout 18363df

# ---- Backend-specific GPU package install (this is where CUDA/ROCm actually diverge) ----
ENV PIP_NO_CACHE_DIR=1
RUN if [ "$GPU_BACKEND" = "cuda" ]; then \
        pip install torch torchvision; \
    elif [ "$GPU_BACKEND" = "rocm" ]; then \
        pip install torch==2.12.1 torchvision==0.27.1 --index-url https://download.pytorch.org/whl/rocm7.2; \
    else \
        echo "Unknown GPU_BACKEND: $GPU_BACKEND" && exit 1; \
    fi

# ---- Shared application dependencies ----
RUN pip install \
        scipy \
        certifi \
        torch-geometric \
        gemmi \
        biopython \
        tqdm \
        natsort \
        omegaconf \
        rdkit \
        einops \
        hydra-core \
        torchtyping \
        dm-tree \
        timm \
        jaxtyping \
        joblib \
        pandas && \
    pip install -e /app/fampnn

ENV PYTHONPATH="/app/fampnn"

WORKDIR /app/fampnn
ENTRYPOINT ["/bin/bash", "-c", "exec \"$@\"", "--"]
CMD ["/bin/bash", "--norc"]
