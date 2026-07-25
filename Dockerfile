FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        zsh \
        ca-certificates \
        curl \
        git \
        jq \
        less \
        ripgrep \
        sudo \
        build-essential \
        python3 \
        python3-pip \
        pipx \
        cmake \
        pkg-config \
        sqlite3 \
        libssl-dev \
        fd-find \
        bat \
        tree \
        unzip \
        zip \
        tmux \
        htop \
        shellcheck \
        default-jdk \
        golang-go \
        rustc \
        cargo \
        ruby-full \
        php-cli \
        perl \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && npm install --global --no-fund --no-audit \
        typescript \
        tsx \
        eslint \
        prettier \
    && ln -s /usr/bin/fdfind /usr/local/bin/fd \
    && ln -s /usr/bin/batcat /usr/local/bin/bat \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --shell /bin/zsh agent \
    && echo "agent ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/agent \
    && chmod 0440 /etc/sudoers.d/agent \
    && mkdir -p /workspace /home/agent/.local/bin /home/agent/.npm-global/bin \
    && chown -R agent:agent /workspace /home/agent

# Install Zap and its default .zshrc for the non-root interactive user.
RUN su --login --shell /bin/zsh agent --command 'zsh <(curl -fsSL https://raw.githubusercontent.com/zap-zsh/zap/master/install.zsh) --branch release-v1'

ENV HOME=/home/agent
ENV COLORTERM=truecolor
ENV PATH=/home/agent/.local/bin:/home/agent/.npm-global/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

WORKDIR /workspace
USER agent

CMD ["/bin/zsh"]
