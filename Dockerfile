# Base Ubuntu image
FROM ubuntu:20.04

# Set environment variables to prevent interactive prompts during installation
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC

# Install common dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    cmake \
    python3 \
    python3-pip \
    wget \
    curl \
    libfl2 \
    libfl-dev \
    bison \
    flex \
    libreadline-dev \
    gawk \
    tcl-dev \
    libffi-dev \
    pkg-config \
    libboost-system-dev \
    libboost-python-dev \
    libboost-filesystem-dev \
    libboost-thread-dev \
    zlib1g-dev \
    libevent-dev \
    autoconf \
    gtkwave \
    && rm -rf /var/lib/apt/lists/*

# Install Verilator (from source for a specific version)
RUN apt-get update && apt-get install -y help2man # Verilator dependency
ENV VERILATOR_VERSION v4.210
# Check latest stable release from https://github.com/verilator/verilator/tags
RUN git clone --branch ${VERILATOR_VERSION} https://github.com/verilator/verilator /tmp/verilator_src \
    && cd /tmp/verilator_src \
    && autoconf \
    && ./configure \
    && make -j$(nproc) \
    && make install \
    && cd / \
    && rm -rf /tmp/verilator_src

# Install Icarus Verilog and Yosys
RUN apt-get update && apt-get install -y \
    iverilog \
    yosys \
    && rm -rf /var/lib/apt/lists/*

# Install RISC-V GNU Toolchain (prebuilt rv32imc)
# For other configurations, visit https://github.com/xpack-dev-tools/riscv-none-embed-gcc-xpack/releases/
# or https://github.com/sifive/freedom-tools/releases
ENV RISCV_TOOLCHAIN_VERSION "13.2.0-2"
ENV RISCV_TOOLCHAIN_TAR "xpack-riscv-none-embed-gcc-${RISCV_TOOLCHAIN_VERSION}-linux-x64.tar.gz"
ENV RISCV_TOOLCHAIN_URL "https://github.com/xpack-dev-tools/riscv-none-embed-gcc-xpack/releases/download/v${RISCV_TOOLCHAIN_VERSION}/${RISCV_TOOLCHAIN_TAR}"

RUN wget ${RISCV_TOOLCHAIN_URL} -O /tmp/${RISCV_TOOLCHAIN_TAR} \
    && mkdir -p /opt/riscv \
    && tar -xzf /tmp/${RISCV_TOOLCHAIN_TAR} -C /opt/riscv --strip-components=1 \
    && rm /tmp/${RISCV_TOOLCHAIN_TAR}

# Add RISC-V toolchain to PATH
ENV PATH="/opt/riscv/bin:${PATH}"

# Alternative: Build RISC-V toolchain from source (can take a very long time)
# This typically builds a newlib/ELF toolchain.
# RUN git clone --recursive https://github.com/riscv/riscv-gnu-toolchain /tmp/riscv-gnu-toolchain-src
# RUN cd /tmp/riscv-gnu-toolchain-src && ./configure --prefix=/opt/riscv --with-arch=rv32imc --with-abi=ilp32 \
# && make -j$(nproc) \
# && make linux -j$(nproc) # If you need linux support, otherwise just 'make' for newlib
# RUN cd / && rm -rf /tmp/riscv-gnu-toolchain-src
# ENV PATH="/opt/riscv/bin:${PATH}"


# Set default working directory
WORKDIR /project

# Copy project files into the container (optional, can be done with docker run -v)
# COPY . /project

# Default command when container starts
CMD ["bash"]

# Verify installations (optional, for Docker build debugging)
# RUN verilator --version
# RUN iverilog -V
# RUN yosys -V
# RUN riscv32-unknown-elf-gcc --version
# RUN riscv-none-embed-gcc --version
