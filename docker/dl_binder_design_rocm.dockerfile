FROM quay.io/pawsey/rocm-mpich-base:rocm6.2.4-mpich3.4.3-ubuntu24.04

# Use bash to support string substitution.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# ROCm environment
ENV ROCM_RELEASE 6.2.4
ENV ROCM_PATH /opt/rocm-$ROCM_RELEASE
ENV PATH $ROCM_PATH/bin:$ROCM_PATH/llvm/bin:$PATH
ENV LD_LIBRARY_PATH $LD_LIBRARY_PATH:$ROCM_PATH/lib:/opt/miniforge3/lib
ENV JAX_PLATFORMS "rocm,cpu"
ENV PIP_NO_CACHE_DIR=true
ENV PIP_ROOT_USER_ACTION=ignore
ENV PIP_BREAK_SYSTEM_PACKAGES=1

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update --quiet \
    && apt-get install --no-install-recommends --yes --quiet \
        build-essential \
        git \
        python3-pip \
        wget \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get autoremove --yes \
    && apt-get clean

# Retrieve dl_binder_design and check out the requested revision.
RUN git clone https://github.com/PapenfussLab/dl_binder_design.git /dl_binder_design && \
    git -C /dl_binder_design checkout f159e83 && \
    git clone https://github.com/dauparas/ProteinMPNN.git /dl_binder_design/ProteinMPNN

    
# Install pip packages.
ENV PIP_NO_CACHE_DIR=true
ENV PIP_ROOT_USER_ACTION=ignore
ENV UV_NO_CACHE=1
ENV UV_LINK_MODE=copy
ENV UV_PYTHON_INSTALL_DIR=/opt/uv-python
ENV VIRTUAL_ENV=/opt/venv
ENV PATH=/opt/venv/bin:${PATH}

RUN pip install --break-system-packages uv \
    && uv venv --python /usr/bin/python3.12 /opt/venv

RUN uv pip install \
        biopython==1.86 \
        dm-haiku==0.0.15 \
        dm-tree==0.1.9 \
        flax==0.10.4 \
        ml-collections==1.1.0 \
        ml_dtypes==0.5.3 \
        mock==5.2.0 \
        'numpy<2.0' \
        'openmm[hip6]' \
        pdbfixer \
        pyfaspr \
        tensorflow-cpu==2.20.0

RUN uv pip install --index-url https://download.pytorch.org/whl/rocm6.2.4 \
        torch==2.6.0 \
        torchvision==0.21.0

RUN uv pip install https://github.com/ROCm/jax/releases/download/rocm-jax-v0.4.34/jaxlib-0.4.34-cp312-cp312-manylinux_2_28_x86_64.whl && \
    uv pip install https://github.com/ROCm/jax/releases/download/rocm-jax-v0.4.34/jax_rocm60_pjrt-0.4.34-py3-none-manylinux_2_28_x86_64.whl https://github.com/ROCm/jax/releases/download/rocm-jax-v0.4.34/jax_rocm60_plugin-0.4.34-cp312-cp312-manylinux_2_28_x86_64.whl && \
    uv pip install https://github.com/ROCm/jax/archive/refs/tags/rocm-jax-v0.4.34.tar.gz

ENV PYTHONPATH=/dl_binder_design

COPY dl_binder_design_rocm.dockerfile /opt/docker-recipes/
LABEL org.opencontainers.image.authors="Sarah Beecroft <sarah.beecroft@csiro.au>"

# XLA flags fix couple of runtime bugs
ENV XLA_FLAGS='--xla_gpu_enable_command_buffer= --xla_gpu_autotune_level=0'
ENV HIP_VISIBLE_DEVICES="0"
ENV ROCR_VISIBLE_DEVICES="0"
ENV AMD_COMGR_CACHE_DIR=/tmp/amd_comgr_cache
ENV PYTHONUNBUFFERED=1