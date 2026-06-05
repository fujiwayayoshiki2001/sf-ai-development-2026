FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Tokyo
ENV LANG=ja_JP.UTF-8
ENV LC_ALL=ja_JP.UTF-8

# 基本パッケージ
RUN apt-get update && apt-get install -y \
    sudo \
    curl \
    wget \
    ca-certificates \
    gnupg \
    lsb-release \
    locales \
    git \
    vim \
    unzip \
    openjdk-17-jdk \
    python3 \
    python3-pip \
    && locale-gen ja_JP.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

# Zscaler 証明書（必須）
COPY zscaler-root.cer /usr/local/share/ca-certificates/zscaler.crt
RUN update-ca-certificates

# Node.js / npm が Zscaler 証明書を信頼するように設定
ENV NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt

# Node.js 20
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Salesforce CLI
RUN npm install -g @salesforce/cli@latest \
    && sf --version

# GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
       > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update \
    && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# 開発ユーザーの作成
ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=1000
RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m -s /bin/bash $USERNAME \
    && echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/$USERNAME

USER $USERNAME
WORKDIR /home/$USERNAME

# Claude Code（ユーザー権限でインストール）
RUN curl -fsSL https://claude.ai/install.sh | bash \
    && echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc

ENV PATH="/home/${USERNAME}/.local/bin:${PATH}"

CMD ["/bin/bash"]
