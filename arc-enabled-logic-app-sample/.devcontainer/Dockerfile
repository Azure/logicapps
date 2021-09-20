# See here for image contents: https://github.com/microsoft/vscode-dev-containers/tree/v0.177.0/containers/dotnet/.devcontainer/base.Dockerfile

FROM mcr.microsoft.com/vscode/devcontainers/dotnet:3.1

# Configure apt and install packages
RUN apt-get update \
    && apt-get -y install --no-install-recommends \
        apt-utils \
        dialog  \
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
    && curl -sL https://packages.microsoft.com/keys/microsoft.asc | (OUT=$(apt-key add - 2>&1) || echo $OUT) \
    && echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $(lsb_release -cs) main" > /etc/apt/sources.list.d/azure-cli.list \
    && echo "deb [arch=amd64] https://packages.microsoft.com/repos/microsoft-ubuntu-$(lsb_release -cs)-prod $(lsb_release -cs) main" > /etc/apt/sources.list.d/dotnetdev.list \
    && curl https://baltocdn.com/helm/signing.asc | apt-key add \ 
    && echo "deb https://baltocdn.com/helm/stable/debian/ all main" | tee /etc/apt/sources.list.d/helm-stable-debian.list \
    && curl -sL https://deb.nodesource.com/setup_12.x | bash - \
    && apt-get update \
    && apt-get -y install --no-install-recommends \ 
        apt-utils \
        dialog  \
        azure-cli \ 
        azure-functions-core-tools-3 \
        helm=3.5.0-1 \
        nodejs \
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
    && npm install -g azurite
    # install k9s
RUN mkdir -p /home/${USERNAME}/.k9s \
    && K9S_VERSION=$(basename "$(curl -fsSL -o /dev/null -w "%{url_effective}" https://github.com/derailed/k9s/releases/latest)") \
    && curl -Lo ./k9s.tar.gz https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_x86_64.tar.gz \
    && mkdir k9s \
    && tar xvzf k9s.tar.gz -C ./k9s \
    && chmod 755 ./k9s/k9s \
    && mv ./k9s/k9s /usr/local/bin/k9s \
    && rm -rf k9s.tar.gz k9s \
    && localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8

ENV LANG en_US.UTF-8
