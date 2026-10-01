ARG GPU_BACKEND=cuda

# ---- Backend-specific base images ----
FROM nvidia/cuda:12.8.0-base-ubuntu24.04 AS base-cuda
FROM rocm/dev-ubuntu-24.04:latest AS base-rocm

# Selects one of the above as the working base for the rest of the build
FROM base-${GPU_BACKEND} AS final
ARG GPU_BACKEND

LABEL org.opencontainers.image.description="BindCraft container (${GPU_BACKEND} backend)"

# ---- Shared system deps (identical for both backends) ----
RUN apt-get -q update && \
    DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
        git wget ca-certificates build-essential libgfortran5 && \
    apt-get autoremove -y && apt-get clean && rm -rf /var/lib/apt/lists/*

# ---- Shared Miniforge + conda env creation ----
RUN wget -q https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh -O /tmp/miniforge.sh && \
    bash /tmp/miniforge.sh -b -p /opt/conda && rm /tmp/miniforge.sh
ENV PATH="/opt/conda/bin:${PATH}"

RUN /opt/conda/bin/conda create -n BindCraft python=3.10 -y && \
    . /opt/conda/etc/profile.d/conda.sh && conda activate BindCraft && \
    conda install -c conda-forge \
        pip pandas matplotlib 'numpy<2.0.0' biopython scipy pdbfixer openmm seaborn \
        tqdm jupyter ffmpeg fsspec py3dmol chex dm-haiku 'flax<0.10.0' \
        dm-tree joblib ml-collections immutabledict optax -y && \
    conda clean -a -y

# ---- Backend-specific GPU package install (this is where CUDA/ROCm actually diverge) ----
ENV PIP_NO_CACHE_DIR=1
RUN . /opt/conda/etc/profile.d/conda.sh && conda activate BindCraft && \
    if [ "$GPU_BACKEND" = "cuda" ]; then \
        conda install -c nvidia 'cuda-nvcc=12.*' 'cuda-version=12' cudnn -y && \
        pip install --upgrade "jax[cuda12]"; \
    elif [ "$GPU_BACKEND" = "rocm" ]; then \
        pip install --upgrade jax jaxlib -f https://storage.googleapis.com/jax-releases/jax_rocm_releases.html; \
    else \
        echo "Unknown GPU_BACKEND: $GPU_BACKEND" && exit 1; \
    fi

# ---- Shared application layer ----
RUN . /opt/conda/etc/profile.d/conda.sh && conda activate BindCraft && \
    pip install git+https://github.com/sokrypton/ColabDesign.git --no-deps && \
    pip install freesasa

RUN git clone https://github.com/PapenfussLab/FreeBindCraft.git /opt/BindCraft && \
    git -C /opt/BindCraft checkout 7a202e2 && \
    chmod +x /opt/BindCraft/functions/DAlphaBall.gcc \
             /opt/BindCraft/functions/dssp \
             /opt/BindCraft/functions/FASPR \
             /opt/BindCraft/functions/sc

ENV CONDA_DEFAULT_ENV=BindCraft
WORKDIR /opt/BindCraft
ENTRYPOINT ["/bin/bash", "-c", "source /opt/conda/etc/profile.d/conda.sh && conda activate BindCraft && exec \"$@\"", "--"]
CMD ["/bin/bash", "--norc"]
