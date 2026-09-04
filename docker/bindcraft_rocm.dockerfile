FROM quay.io/pawsey/rocm-mpich-base:rocm7.0.2-mpich3.4.3-ubuntu24.04

# Use bash to support string substitution.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update --quiet \
    && apt-get install --no-install-recommends --yes --quiet \
      build-essential \
      ca-certificates \
      curl \
      git \
      rsync \
      libgfortran5 \
      tmux \
      wget \
      pkg-config \
      procps \
      ocl-icd-libopencl1 \
      clinfo \
      unzip \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get autoremove --yes \
    && apt-get clean

# ROCm environment
ENV ROCM_RELEASE 7.0.2
ENV ROCM_PATH /opt/rocm-$ROCM_RELEASE
ENV PATH $ROCM_PATH/bin:$ROCM_PATH/llvm/bin:$PATH
ENV LD_LIBRARY_PATH $LD_LIBRARY_PATH:$ROCM_PATH/lib
ENV JAX_PLATFORMS="rocm,cpu"
ENV PIP_NO_CACHE_DIR=true

WORKDIR /app

# Install miniforge (mamba)
RUN set -eux ; \
    curl -L -O "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-$(uname)-$(uname -m).sh" ; \
    bash Miniforge3-$(uname)-$(uname -m).sh -b -p /opt/miniforge3 -s ; \
    rm -rf ./Miniforge3-*

# Put mamba on PATH
ENV PATH /opt/miniforge3/bin:$PATH

# Clone FreeBindCraft repository and checkout the requested revision
RUN git clone https://github.com/PapenfussLab/FreeBindCraft.git /opt/BindCraft && \
    git -C /opt/BindCraft checkout 7a202e2 && \
    chmod +x /opt/BindCraft/functions/DAlphaBall.gcc && \
    chmod +x /opt/BindCraft/functions/dssp && \
    chmod +x /opt/BindCraft/functions/FASPR && \
    chmod +x /opt/BindCraft/functions/sc

# Copy the environment file and Dockerfile into the image for reproducibility.
COPY bindcraft_rocm.dockerfile bindcraft.yml /opt/docker-recipes/

# Install the conda environment and ColabDesign (no dependencies for ColabDesign, since they are already in the conda env).
RUN mamba env update -n base -y -f /opt/docker-recipes/bindcraft.yml && \
    mamba clean -afy
RUN pip install git+https://github.com/sokrypton/ColabDesign.git --no-deps

# Default environment
ENV PYTHONUNBUFFERED=1 \
    BINDCRAFT_HOME=/opt/BindCraft

ENV OPENMM_PLATFORM_ORDER=HIP,OpenCL,CPU \
    OPENMM_DEFAULT_PLATFORM=HIP
ENV XLA_FLAGS='--xla_gpu_enable_command_buffer= --xla_gpu_autotune_level=0'
ENV AMD_COMGR_CACHE_DIR=/tmp/amd_comgr_cache

LABEL org.opencontainers.image.authors="Sarah Beecroft <sarah.beecroft@csiro.au>" \
      org.opencontainers.image.description="FreeBindCraft v1.0.5, no PyRosetta with ROCm7.0.2 support on Ubuntu 24.04 for AMD GPUs" \
      org.opencontainers.image.source="https://github.com/PawseySC/GPU_biology/tree/main/FreeBindCraft/rocm7.0.2" \
      org.opencontainers.image.name="freebindcraft_1.0.5_rocm7.0.2_ubuntu24.04" \
      Python_version="3.10"
