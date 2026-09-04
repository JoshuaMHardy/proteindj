FROM quay.io/pawsey/alphafold2:v2.3.2_rocm6.2.4

# Clone the dl_binder_design repository
RUN git clone https://github.com/PapenfussLab/dl_binder_design.git /dl_binder_design && \
    git -C /dl_binder_design checkout f159e83 && \
    git clone https://github.com/dauparas/ProteinMPNN.git /dl_binder_design/ProteinMPNN

ENV AMD_COMGR_CACHE_DIR=/tmp/comgr_cache
COPY alphafold2_rocm.dockerfile /opt/docker-recipes/af2_rocm.dockerfile

LABEL org.opencontainers.image.authors="Sarah Beecroft <sarah.beecroft@csiro.au>" \
      org.opencontainers.image.description="af2 for proteinDJ with ROCm6.4.2 on Ubuntu 24.04 for AMD GPUs"
