FROM mcr.microsoft.com/dotnet/sdk:10.0

# Versión oficial de Godot 4.7.2 .NET Edition
ARG GODOT_VERSION="4.7.2"
ARG GODOT_RELEASE="stable"

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
    tmux \
    jq \
    libfontconfig1 \
    libglu1-mesa \
    libxcursor1 \
    libxi6 \
    libxinerama1 \
    libxrandr2 \
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

WORKDIR /workspaces/GodotNakama

CMD ["sleep", "infinity"]