# Copyright (c) 2020 Red Hat, Inc.
# This program and the accompanying materials are made
# available under the terms of the Eclipse Public License 2.0
# which is available at https://www.eclipse.org/legal/epl-2.0/
#
# SPDX-License-Identifier: EPL-2.0
#
FROM registry.access.redhat.com/ubi8-minimal:8.10-1130

ARG KUBERNETES_VERSION=v1.31.0

RUN export ARCH="$(uname -m)" && if [[ ${ARCH} == "x86_64" ]]; then export ARCH="amd64"; elif [[ ${ARCH} == "aarch64" ]]; then export ARCH="arm64"; fi && \
    microdnf install -y openssl && \
    cd /usr/local/bin && \
    curl -sLO https://storage.googleapis.com/kubernetes-release/release/${KUBERNETES_VERSION}/bin/linux/${ARCH}/kubectl && \
    chmod +x kubectl && \
    microdnf clean all

COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]