ARG BASE_IMAGE_CUDA_VERSION=11.4.3
ARG BASE_IMAGE_UBUNTU_VERSION=20.04

FROM nvidia/cuda:${BASE_IMAGE_CUDA_VERSION}-devel-ubuntu${BASE_IMAGE_UBUNTU_VERSION} AS base

# Dockerfile inspired from various sources
# Base image: https://github.com/Amber-MD/common-dockerfiles/blob/master/debian-based/Dockerfile
# Adding miniforge: https://github.com/conda-forge/miniforge-images/blob/master/ubuntu/Dockerfile

ENV CUDA_HOME=/usr/local/cuda
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8
ENV DEBIAN_FRONTEND=noninteractive

ARG MINIFORGE_NAME=Miniforge3
ARG MINIFORGE_VERSION=24.9.2-0

# Setup conda so it doesn't need activated later
ENV CONDA_DIR=/opt/conda
ENV PATH=${CONDA_DIR}/bin:${PATH}

# APT install with cleanup
RUN apt-get update > /dev/null && \
    apt-get upgrade -y && \
    apt-get install --no-install-recommends --yes \
    wget \
    bzip2 \
    ca-certificates \
    git \
    tini \
    cmake \
    tcsh \
    make \ 
    gcc \
    gfortran \
    flex \ 
    bison \
    patch \ 
    bc \
    xorg-dev \
    libz-dev \
    libbz2-dev \
    > /dev/null && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Miniforge install with cleanup
# Install conda packages now so we can use -DDOWNLOAD_MINICONDA=FALSE later
# Maybe also need pytest swig cython
RUN wget --no-hsts --quiet https://github.com/conda-forge/miniforge/releases/download/${MINIFORGE_VERSION}/${MINIFORGE_NAME}-${MINIFORGE_VERSION}-Linux-$(uname -m).sh -O /tmp/miniforge.sh && \
    /bin/bash /tmp/miniforge.sh -b -p ${CONDA_DIR} && \
    rm /tmp/miniforge.sh && \
    conda install -y numpy scipy matplotlib && \
    conda clean --tarballs --index-cache --packages --yes && \
    find ${CONDA_DIR} -follow -type f -name '*.a' -delete && \
    find ${CONDA_DIR} -follow -type f -name '*.pyc' -delete && \
    conda clean --force-pkgs-dirs --all --yes 

WORKDIR /amber

FROM base AS complier

ADD --link Amber24.tar.bz2 .
ADD --link AmberTools24.tar.bz2 .
RUN cd amber24_src && ./update_amber --update
COPY --chown=1000:1000 run_cmake_injected /amber/amber24_src/build/
RUN cd amber24_src/build && ./run_cmake_injected
RUN cd amber24_src/build && make install -j12

FROM nvidia/cuda:${BASE_IMAGE_CUDA_VERSION}-runtime-ubuntu${BASE_IMAGE_UBUNTU_VERSION} AS final
COPY --from=complier /amber/amber24/ /amber/amber24/
# This just keeps the container alive so we can inspect files etc
ENTRYPOINT ["tini", "--"]
CMD [ "/bin/bash", "-c", "while true; do sleep 30; done;"]

ENV CUDA_HOME=/usr/local/cuda
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8
# Setup conda so it doesn't need activated later
ENV CONDA_DIR=/opt/conda
ENV PATH=${CONDA_DIR}/bin:${PATH}

COPY --from=complier ${CONDA_DIR} ${CONDA_DIR}

# APT install with cleanup
RUN apt-get update > /dev/null && \
    apt-get upgrade -y && \
    apt-get install --no-install-recommends --yes \
    bzip2 \
    ca-certificates \
    tini \
    tcsh \
    make \
    cmake \
    > /dev/null && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Inline the environment variables set normally by amber.sh. Means this doesn't need to be sourced everytime.
ENV AMBERHOME=/amber/amber24
ENV PATH=${AMBERHOME}/bin:$PATH
ENV LD_LIBRARY_PATH=${AMBERHOME}/lib:$LD_LIBRARY_PATH
ENV PERL5LIB=${AMBERHOME}/lib/perl
ENV PYTHONPATH=${AMBERHOME}/lib/python3.12/site-packages
ENV QUICK_BASIS=${AMBERHOME}/AmberTools/src/quick/basis

WORKDIR ${AMBERHOME}