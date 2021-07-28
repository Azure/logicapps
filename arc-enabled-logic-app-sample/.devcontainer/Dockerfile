# [Choice] .NET Core version: 3.1, 2.1
ARG VARIANT=3.1
FROM mcr.microsoft.com/vscode/devcontainers/dotnet:0-${VARIANT}

# Avoid warnings by switching to noninteractive
ENV DEBIAN_FRONTEND=noninteractive

# install packages
RUN \
    # Install Azure CLI
    curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

RUN \
    # verify git and needed tools are installed
    apt-get -y install \
    git \
    iproute2 \
    procps \
    curl \
    apt-transport-https \
    gnupg2 \
    lsb-release \
    jq \
    software-properties-common \
    zip \
    npm 

RUN \
    # Add source for Azure Functions
    curl -sL https://packages.microsoft.com/keys/microsoft.asc | (OUT=$(apt-key add - 2>&1) || echo $OUT) \
    && echo "deb [arch=amd64] https://packages.microsoft.com/repos/microsoft-ubuntu-$(lsb_release -cs)-prod $(lsb_release -cs) main" > /etc/apt/sources.list.d/dotnetdev.list \
    # Add source for Docker CLI
    && curl -fsSL https://download.docker.com/linux/$(lsb_release -is | tr '[:upper:]' '[:lower:]')/gpg | apt-key add - 2>/dev/null \
    && echo "deb [arch=amd64] https://download.docker.com/linux/$(lsb_release -is | tr '[:upper:]' '[:lower:]') $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list \
    # Add source for Helm
    && curl https://baltocdn.com/helm/signing.asc | apt-key add \ 
    && echo "deb https://baltocdn.com/helm/stable/debian/ all main" | tee /etc/apt/sources.list.d/helm-stable-debian.list \
    && apt-get update \
    && apt-get -y install --no-install-recommends \ 
        apt-utils \
        dialog  \
        # Install Func CLI
        azure-functions-core-tools-3 \
        # Install Docker CLI
        docker-ce-cli \
        # Install Helm
        helm=3.5.0-1 \
    # Install Azure CLI Extensions
    && az aks install-cli \
    # Install bicep
    && az bicep install \
    && az extension add -n application-insights \
    && az extension add --upgrade --yes -n connectedk8s \
    && az extension add --upgrade --yes -n customlocation \
    && az extension add --upgrade --yes -n k8s-extension \
    && az extension add --yes --source "https://aka.ms/appsvc/appservice_kube-latest-py2.py3-none-any.whl" \
    && az extension add --yes --source "https://aka.ms/logicapp-latest-py2.py3-none-any.whl" \    
    # Install Azurite
    && npm install -g azurite \
    && apt-get clean -y && rm -rf /var/lib/apt/lists/*

ENV PATH=/root/.azure/bin:${PATH}
ENV DOCKER_HOST=tcp://host.docker.internal:2375

# Switch back to dialog for any ad-hoc use of apt-get
ENV DEBIAN_FRONTEND=dialog
