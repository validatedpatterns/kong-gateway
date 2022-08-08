FROM registry.access.redhat.com/ubi8/ubi-minimal:8.6

ENV LANG='en_US.UTF-8' LANGUAGE='en_US:en'
RUN microdnf install bash dnf wget tar\
    && microdnf update \
    && microdnf clean all 

ARG OCP_VERSION=4.9.10
ARG USERNAME=readfile
ARG USER_UID=1000
ARG USER_GID=$USER_UID

RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME

RUN wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OCP_VERSION}/openshift-client-linux-${OCP_VERSION}.tar.gz \
    && tar -xzf openshift-client-linux-${OCP_VERSION}.tar.gz -C /usr/bin \
    && rm -f openshift-client-linux-${OCP_VERSION}.tar.gz /usr/bin/README.md \
    && chmod +x /usr/bin/oc \
    && chmod +x /usr/bin/kubectl

RUN dnf install openssl jq -y 

RUN curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
RUN chmod +x /usr/local/bin/argocd

USER $USERNAME

WORKDIR /home/$USERNAME