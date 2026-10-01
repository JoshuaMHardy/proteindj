# TEMPLATE: copy this file to Dockerfile.<tool>.dockerfile and replace every <PLACEHOLDER>.
# This file is not referenced by docker-bake.hcl, so it is never built directly.
# See docs/dev/adding_a_new_container.md for the full walkthrough.

ARG GPU_BACKEND=cuda

# ---- Backend-specific base images ----
# Keep these pinned to a specific tag (not ":latest") so builds are reproducible.
FROM <CUDA_BASE_IMAGE> AS base-cuda
FROM <ROCM_BASE_IMAGE> AS base-rocm

# Selects one of the above as the working base for the rest of the build
FROM base-${GPU_BACKEND} AS final
ARG GPU_BACKEND

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

LABEL org.opencontainers.image.authors="<YOUR_NAME>" \
      org.opencontainers.image.description="<TOOL_NAME> container (${GPU_BACKEND} backend)"

# ---- Shared system deps (identical for both backends) ----
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update --quiet && \
    apt-get install --no-install-recommends --yes --quiet \
        build-essential \
        git \
        wget \
        software-properties-common \
        <EXTRA_APT_PACKAGES> && \
    rm -rf /var/lib/apt/lists/* && \
    apt-get autoremove --yes && \
    apt-get clean

# ---- Shared Miniforge + Python env (identical for both backends) ----
RUN wget -q https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh -O /tmp/miniforge.sh && \
    bash /tmp/miniforge.sh -b -p /opt/conda && rm /tmp/miniforge.sh
ENV PATH="/opt/conda/bin:${PATH}"

RUN mamba install -y -c conda-forge -c bioconda python=<PYTHON_VERSION> && \
    mamba clean -afy

# ---- Shared application source ----
# Pin a commit so rebuilds are reproducible and don't silently pick up upstream changes.
RUN git clone <REPO_URL> <APP_DIR> && \
    git -C <APP_DIR> checkout <COMMIT_SHA>

# ---- Backend-specific GPU package install (this is where CUDA/ROCm actually diverge) ----
# Before filling this in, confirm the tool's GPU framework (JAX/DGL/PyTorch/OpenMM/etc.) actually
# has a working ROCm build — see docs/dev/adding_a_new_container.md for known gaps.
ENV PIP_NO_CACHE_DIR=1
RUN if [ "$GPU_BACKEND" = "cuda" ]; then \
        pip install <CUDA_GPU_PACKAGES>; \
    elif [ "$GPU_BACKEND" = "rocm" ]; then \
        pip install <ROCM_GPU_PACKAGES> --index-url <ROCM_PACKAGE_INDEX_URL>; \
    else \
        echo "Unknown GPU_BACKEND: $GPU_BACKEND" && exit 1; \
    fi

# ---- Shared application dependencies ----
RUN pip install \
        <SHARED_PIP_PACKAGES> && \
    pip install -e <APP_DIR>

ENV PYTHONPATH="<APP_DIR>"

WORKDIR <APP_DIR>
ENTRYPOINT ["/bin/bash", "-c", "exec \"$@\"", "--"]
CMD ["/bin/bash", "--norc"]
