FROM mcr.microsoft.com/dotnet/sdk:10.0

# Version pinning
ARG GODOT_VERSION="4.7.2"
ARG GODOT_RELEASE="stable"
ARG ASEPRITE_VERSION="1.3.18.6"
ARG SKIA_VERSION="m124-08a5439a6b"
ARG INOCHI_CREATOR_VERSION="0.8.6"

ENV DEBIAN_FRONTEND=noninteractive
ENV DOTNET_CLI_TELEMETRY_OPTOUT=1

# 1. System tools and dependencies (Godot, Aseprite, GIMP, and Inochi2D)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates=20260601~24.04.1 \
    curl=8.5.0-2ubuntu10.15 \
    wget=1.21.4-1ubuntu4.5 \
    unzip=6.0-28ubuntu4.1 \
    git=1:2.43.0-1ubuntu7.3 \
    git-lfs=3.4.1-1ubuntu0.4 \
    clang=1:18.0-59~exp2 \
    clangd=1:18.0-59~exp2 \
    clang-tidy=1:18.0-59~exp2 \
    cmake=3.28.3-1build7 \
    g++=4:13.2.0-7ubuntu1 \
    ninja-build=1.11.1-2 \
    tmux=3.4-1ubuntu0.1 \
    zsh=5.9-6ubuntu2 \
    jq=1.7.1-3ubuntu0.24.04.2 \
    nano=7.2-2ubuntu0.2 \
    btop=1.3.0-1 \
    gimp=2.10.36-3ubuntu0.24.04.1 \
    fonts-noto=20201225-2 \
    zenity=4.0.1-1build3 \
    libsdl2-2.0-0=2.30.0+dfsg-1ubuntu3.1 \
    libfreetype6=2.13.2+dfsg-1ubuntu0.2 \
    fontconfig=2.15.0-1.1ubuntu2 \
    libgl1=1.7.0-1build1 \
    vulkan-tools=1.3.275.0+dfsg1-1 \
    libvulkan1=1.3.275.0-1build1 \
    mesa-vulkan-drivers=25.2.8-0ubuntu0.24.04.4 \
    vulkan-validationlayers=1.3.275.0-1 \
    netcat-openbsd=1.226-1ubuntu2 \
    libfontconfig1-dev=2.15.0-1.1ubuntu2 \
    libfontconfig1=2.15.0-1.1ubuntu2 \
    libgl1-mesa-dev=25.2.8-0ubuntu0.24.04.4 \
    libglu1-mesa=9.0.2-1.1build1 \
    libxcursor1=1:1.2.1-1build1 \
    libxcursor-dev=1:1.2.1-1build1 \
    libxi6=2:1.8.1-1build1 \
    libxi-dev=2:1.8.1-1build1 \
    libxinerama1=2:1.1.4-3build1 \
    libxrandr2=2:1.5.2-2build1 \
    libxrandr-dev=2:1.5.2-2build1 \
    libx11-dev=2:1.8.7-1build1 \
    libxkbcommon0=1.6.0-1build1 \
    libxkbcommon-x11-0=1.6.0-1build1 \
    libwayland-client0=1.22.0-2.1build1 \
    libwayland-egl1=1.22.0-2.1build1 \
    libwayland-cursor0=1.22.0-2.1build1 \
    libglx-mesa0=25.2.8-0ubuntu0.24.04.4 \
    libglib2.0-0t64=2.80.0-6ubuntu3.9 \
    libdbus-1-3=1.14.10-4ubuntu4.1 \
    dbus-x11=1.14.10-4ubuntu4.1 \
    libpulse0=1:16.1+dfsg1-2ubuntu10.1 \
    libasound2t64=1.2.11-1ubuntu0.3 \
    libasound2-plugins=1.2.7.1-1ubuntu5 \
    pulseaudio-utils=1:16.1+dfsg1-2ubuntu10.1 \
    && rm -rf /var/lib/apt/lists/*

RUN git lfs install --system

# 2. Download and install Godot 4.7.2 .NET version (labeled as mono)
RUN GODOT_BUILD="Godot_v${GODOT_VERSION}-${GODOT_RELEASE}_mono_linux_x86_64" && \
    wget --quiet https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-${GODOT_RELEASE}/${GODOT_BUILD}.zip && \
    unzip ${GODOT_BUILD}.zip -d /opt/godot && \
    rm ${GODOT_BUILD}.zip && \
    mv /opt/godot/${GODOT_BUILD} /opt/godot/godot-mono && \
    ln -s /opt/godot/godot-mono/Godot_v${GODOT_VERSION}-${GODOT_RELEASE}_mono_linux.x86_64 /usr/local/bin/godot

# 3. Build and install Aseprite with Skia
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

# 4. Download and install precompiled Inochi Creator v0.8.6
RUN mkdir -p /opt/inochi-creator && \
    wget --quiet https://github.com/Inochi2D/inochi-creator/releases/download/v${INOCHI_CREATOR_VERSION}/inochi-creator-linux.zip -O /tmp/inochi-creator.zip && \
    unzip -q /tmp/inochi-creator.zip -d /opt/inochi-creator && \
    chmod +x /opt/inochi-creator/inochi-creator && \
    rm /tmp/inochi-creator.zip

WORKDIR /home/ubuntu/GodotNakama

CMD ["sleep", "infinity"]