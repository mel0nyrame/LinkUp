FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    ANDROID_HOME=/opt/android-sdk \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    FLUTTER_HOME=/opt/flutter \
    PATH="/opt/flutter/bin:/opt/android-sdk/cmdline-tools/latest/bin:/opt/android-sdk/platform-tools:$PATH"

# ── Multi-arch support (Android SDK tools are x86_64; host may be ARM64) ──
# arm64: ports.ubuntu.com (已有，限制为 arm64) | amd64: archive.ubuntu.com (新增)
RUN dpkg --add-architecture amd64 \
    && sed -i '/^Components:/a Architectures: arm64' /etc/apt/sources.list.d/ubuntu.sources \
    && printf 'deb [arch=amd64] http://archive.ubuntu.com/ubuntu noble main restricted universe multiverse\n' > /etc/apt/sources.list.d/amd64.list \
    && printf 'deb [arch=amd64] http://archive.ubuntu.com/ubuntu noble-updates main restricted universe multiverse\n' >> /etc/apt/sources.list.d/amd64.list \
    && printf 'deb [arch=amd64] http://archive.ubuntu.com/ubuntu noble-security main restricted universe multiverse\n' >> /etc/apt/sources.list.d/amd64.list \
    && printf 'deb [arch=amd64] http://archive.ubuntu.com/ubuntu noble-backports main restricted universe multiverse\n' >> /etc/apt/sources.list.d/amd64.list

# ── System dependencies ──────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl git unzip xz-utils zip wget \
    openjdk-17-jdk-headless \
    cmake ninja-build clang pkg-config \
    libgtk-3-dev liblzma-dev libstdc++-12-dev \
    libc6:amd64 libstdc++6:amd64 zlib1g:amd64 \
    && rm -rf /var/lib/apt/lists/*

# ── Flutter SDK (master channel, needed for Dart ^3.12.0-239.0.dev) ──
RUN git clone --depth 1 --branch master \
    https://github.com/flutter/flutter.git $FLUTTER_HOME \
    && flutter --version

# ── Android SDK command-line tools ───────────────────────────────
RUN mkdir -p $ANDROID_HOME/cmdline-tools \
    && curl -sL https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip \
       -o /tmp/sdk.zip \
    && unzip -q /tmp/sdk.zip -d $ANDROID_HOME/cmdline-tools \
    && mv $ANDROID_HOME/cmdline-tools/cmdline-tools $ANDROID_HOME/cmdline-tools/latest \
    && rm /tmp/sdk.zip

# ── Android SDK packages ─────────────────────────────────────────
# Flutter 3.45 master 要求: SDK 36 + BuildTools 28.0.3 + NDK 28.2
RUN yes | sdkmanager --licenses > /dev/null 2>&1 \
    && sdkmanager --install \
        "platform-tools" \
        "platforms;android-36" \
        "build-tools;28.0.3" \
        "ndk;28.2.13676358" \
        "cmake;3.22.1"

# ── Flutter config ───────────────────────────────────────────────
RUN flutter config --android-sdk $ANDROID_HOME \
    && yes | flutter doctor --android-licenses \
    && flutter doctor -v

WORKDIR /workspace
