# Local Linux test controller, never an FFIDO runtime image.
# Supply all four prepared inputs; scratch defaults intentionally cannot build.
ARG DOCKER_TOOLS=scratch
ARG ENVOY_TOOLS=scratch
ARG QA_DISTRIBUTION=scratch
ARG QA_BUILD_TOOLS=scratch
FROM ${DOCKER_TOOLS} AS docker-tools
FROM ${ENVOY_TOOLS} AS envoy-tools
FROM ${QA_BUILD_TOOLS} AS build-tools
FROM ${QA_DISTRIBUTION}
USER root
COPY --from=docker-tools /usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker-tools /usr/local/libexec/docker/cli-plugins/ /usr/local/libexec/docker/cli-plugins/
COPY --from=envoy-tools /usr/local/bin/envoy /usr/local/bin/envoy
COPY pip/ /tmp/qa-bootstrap/pip/
COPY requirements.txt /tmp/qa-requirements.txt
RUN python3 -m venv --without-pip /qa-python \
    && PYTHONPATH=/tmp/qa-bootstrap /qa-python/bin/python -m pip install --no-cache-dir -r /tmp/qa-requirements.txt \
    && rm -rf /tmp/qa-bootstrap
ENV PATH="/qa-python/bin:${PATH}"
COPY --from=build-tools /src/build/backend/apps/backend/libffido-restore-sync-fault.so /qa-tools/libffido-restore-sync-fault.so
ENTRYPOINT ["/qa-python/bin/python"]
