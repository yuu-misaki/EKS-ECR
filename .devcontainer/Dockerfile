ARG VARIANT="1-3.11-bullseye"
FROM mcr.microsoft.com/vscode/devcontainers/python:${VARIANT}

RUN apt update && apt install -y \
    bash-completion \
    dnsutils \
    default-jre

# kubectlのインストール
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && \
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl.sha256" && \
    echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check && \
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && \
    rm -f kubectl

# Poetryのインストールと設定
RUN curl -sSL https://install.python-poetry.org | POETRY_HOME=/opt/poetry python3 - && \
    cd /usr/local/bin && \
    ln -s /opt/poetry/bin/poetry
RUN su vscode -c "poetry config virtualenvs.create true"
RUN su vscode -c "poetry config virtualenvs.in-project true"

# Helmのインストール
RUN curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 && \
    chmod 700 get_helm.sh && \
    ./get_helm.sh
RUN rm -f get_helm.sh

# k9sのインストール
RUN curl -sS https://webinstall.dev/k9s | bash && \
    bash -c "source ~/.config/envman/PATH.env"


# eksctlのインストール
# for ARM systems, set ARCH to: `arm64`, `armv6` or `armv7`
RUN ARCH=amd64 && \
    PLATFORM=$(uname -s)_$ARCH && \
    curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz" && \
    tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz && \
    sudo mv /tmp/eksctl /usr/local/bin