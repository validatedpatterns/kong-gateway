FROM registry.access.redhat.com/ubi8/ubi-minimal:8.6

ENV LANG='en_US.UTF-8' LANGUAGE='en_US:en'
RUN microdnf install -y wget-1.19.5-10.el8.x86_64 tar-1.30-5.el8.x86_64 openssl-1.1.1k-7.el8_6.x86_64 jq-1.6-3.el8.x86_64 \
    && microdnf update \
    && microdnf clean all 

ARG OCP_VERSION=4.9.10
ARG USERNAME=readfile
ARG USER_UID=1000
ARG USER_GID=$USER_UID

RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME \
    && wget -q https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OCP_VERSION}/openshift-client-linux-${OCP_VERSION}.tar.gz \
    && tar -xzf openshift-client-linux-${OCP_VERSION}.tar.gz -C /usr/bin \
    && rm -f openshift-client-linux-${OCP_VERSION}.tar.gz /usr/bin/README.md \
    && chmod +x /usr/bin/oc \
    && chmod +x /usr/bin/kubectl \
    && wget -q -O /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64 \
    && chmod +x /usr/local/bin/argocd

USER $USERNAME

WORKDIR /home/$USERNAME
