FROM public.ecr.aws/amazonlinux/amazonlinux:2

RUN yum install -y \
    bash \
    unzip \
    curl \
    jq \
    groff \
    less \
    shadow-utils \
    && yum clean all

RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && \
    unzip awscliv2.zip && \
    ./aws/install && \
    rm -rf awscliv2.zip aws

RUN groupadd -g 65522 buildpiper && \
    useradd -u 65522 -g 65522 -m -s /bin/bash buildpiper

RUN mkdir -p /opt/buildpiper/shell-functions

COPY BP-BASE-SHELL-STEPS /opt/buildpiper/shell-functions/
COPY build.sh /opt/buildpiper/build.sh

RUN chown -R buildpiper:buildpiper /opt/buildpiper && \
    chmod +x /opt/buildpiper/build.sh

USER buildpiper
WORKDIR /opt/buildpiper

ENTRYPOINT ["./build.sh"]
