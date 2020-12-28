ARG BUILD_FROM
FROM ${BUILD_FROM}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Add env
ENV LANG C.UTF-8

# Setup base
RUN apk add --no-cache jq openssh-client zip sshpass rsync wget

# Hass.io CLI
ARG BUILD_ARCH
ARG CLI_VERSION
RUN wget -O /usr/bin/ha "https://github.com/home-assistant/cli/releases/download/4.9.0/ha_${BUILD_ARCH}" \
    && chmod a+x /usr/bin/ha

# Copy data
COPY run.sh /
RUN chmod a+x run.sh
CMD [ "/run.sh" ]

# Build arugments
ARG BUILD_DATE
ARG BUILD_REF
ARG BUILD_VERSION

# Labels
LABEL \
    io.hass.name="Remote Backup" \
    io.hass.description="Automatically create and backup HA snapshots using SCP" \
    io.hass.arch="${BUILD_ARCH}" \
    io.hass.type="addon" \
    io.hass.version=${BUILD_VERSION} \
    maintainer="Matheson Steplock <mathesonsteplock.ca>" \
    org.label-schema.description="Automatically create and backup HA snapshots using SCP" \
    org.label-schema.build-date=${BUILD_DATE} \
    org.label-schema.name="Remote Backup" \
    org.label-schema.schema-version="1.0" \
    org.label-schema.usage="https://github.com/ikifar2012/remote-backup-addon/blob/master/README.md" \
    org.label-schema.vcs-ref=${BUILD_REF} \
    org.label-schema.vcs-url="https://github.com/ikifar2012/remote-backup-addon/" \
    org.label-schema.vendor="Matheson's Home Assistant Addons"
