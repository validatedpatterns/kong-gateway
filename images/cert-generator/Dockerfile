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

RUN dnf install openssl -y 

USER $USERNAME

WORKDIR /home/$USERNAME

RUN openssl req -new -x509 -nodes \
    -newkey rsa:2048 \
    -keyout ./cluster.key -out ./cluster.crt -days 1095 -subj "/CN=kong_clustering"

