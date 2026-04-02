FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        git \
        sudo \
        python3 \
        python3-pip \
        build-essential \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --shell /bin/bash agent \
    && echo "agent ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/agent \
    && chmod 0440 /etc/sudoers.d/agent \
    && mkdir -p /workspace \
    && chown -R agent:agent /workspace /home/agent

ENV HOME=/home/agent
WORKDIR /workspace
USER agent

CMD ["/bin/bash"]
