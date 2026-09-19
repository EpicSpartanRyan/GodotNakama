FROM mcr.microsoft.com/dotnet/sdk:10.0

# Versión oficial de Godot 4.7.2 .NET Edition
ARG GODOT_VERSION="4.7.2"
ARG GODOT_RELEASE="stable"
ARG ASEPRITE_VERSION="1.3.18.5"
ARG SKIA_VERSION="m124-08a5439a6b"

ENV DEBIAN_FRONTEND=noninteractive
ENV DOTNET_CLI_TELEMETRY_OPTOUT=1

# 1. Herramientas y dependencias de sistema (compatibles con Ubuntu 24.04 / Noble)
# 1. Herramientas y dependencias de sistema (compatibles con Ubuntu 24.04 / Noble)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    wget \
    unzip \
    git \
    clang \
    cmake \
    g++ \
    ninja-build \
    tmux \
    jq \
    libfontconfig1-dev \
    libfontconfig1 \
    libgl1-mesa-dev \
    libglu1-mesa \
    libxcursor1 \
    libxcursor-dev \
    libxi6 \
    libxi-dev \
    libxinerama1 \
    libxrandr2 \
    libxrandr-dev \
    libx11-dev \
    libxkbcommon0 \
    libxkbcommon-x11-0 \
    libwayland-client0 \
    libwayland-egl1 \
    libwayland-cursor0 \
    libgl1 \
    libglx-mesa0 \
    libglib2.0-0 \
    libdbus-1-3 \
    libpulse0 \
    libasound2t64 \
    && rm -rf /var/lib/apt/lists/*

# 2. Descargar e instalar la versión .NET (etiquetada como mono) de Godot 4.7.2
RUN GODOT_BUILD="Godot_v${GODOT_VERSION}-${GODOT_RELEASE}_mono_linux_x86_64" && \
    wget --quiet https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-${GODOT_RELEASE}/${GODOT_BUILD}.zip && \
    unzip ${GODOT_BUILD}.zip -d /opt/godot && \
    rm ${GODOT_BUILD}.zip && \
    mv /opt/godot/${GODOT_BUILD} /opt/godot/godot-mono && \
    ln -s /opt/godot/godot-mono/Godot_v${GODOT_VERSION}-${GODOT_RELEASE}_mono_linux.x86_64 /usr/local/bin/godot

RUN mkdir -p /opt/aseprite /opt/skia && \
    wget --quiet https://github.com/aseprite/skia/releases/download/${SKIA_VERSION}/Skia-Linux-Release-x64.zip -O /tmp/skia.zip && \
    unzip -q /tmp/skia.zip -d /opt/skia && \
    wget --quiet https://github.com/aseprite/aseprite/releases/download/v${ASEPRITE_VERSION}/Aseprite-v${ASEPRITE_VERSION}-Source.zip -O /tmp/aseprite.zip && \
    unzip -q /tmp/aseprite.zip -d /opt/aseprite && \
    cmake -S /opt/aseprite -B /opt/aseprite/build -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_COMPILER=clang \
        -DCMAKE_CXX_COMPILER=clang++ \
        -DCMAKE_CXX_FLAGS:STRING=-stdlib=libstdc++ \
        -DCMAKE_EXE_LINKER_FLAGS:STRING=-stdlib=libstdc++ \
        -DLAF_BACKEND=skia \
        -DSKIA_DIR=/opt/skia \
        -DSKIA_LIBRARY_DIR=/opt/skia/out/Release-x64 \
        -DSKIA_LIBRARY=/opt/skia/out/Release-x64/libskia.a && \
    cmake --build /opt/aseprite/build --target aseprite --parallel && \
    ln -s /opt/aseprite/build/bin/aseprite /usr/local/bin/aseprite && \
    rm -rf /tmp/aseprite /tmp/*.zip

WORKDIR /workspaces/GodotNakama

CMD ["sleep", "infinity"]