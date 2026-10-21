FROM ubuntu:24.04@sha256:68ee22004a9109b44973313b02ff7b1de250f1de0f5ecb628d73f579aaff33ac AS builder
ENV DEBIAN_FRONTEND=noninteractive CC=clang-19 CXX=clang++-19
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates git cmake make clang-19 libssl-dev libc-ares-dev libre2-dev \
    zlib1g-dev patchelf pkg-config python3 texinfo && rm -rf /var/lib/apt/lists/*
WORKDIR /src
# Keep the expensive native dependency layer independent of application changes.
COPY scripts/release/dependencies.sh scripts/release/dependency_record.py scripts/release/
RUN bash scripts/release/dependencies.sh
# The application adapter applies its patch after native dependencies are cached.
RUN apt-get update && apt-get install -y --no-install-recommends patch \
    && rm -rf /var/lib/apt/lists/*
COPY CMakeLists.txt LICENSE THIRD_PARTY_NOTICES.md README.md CONTRIBUTING.md AGENTS.md .gitignore .clang-format .clang-tidy build.sh Dockerfile .dockerignore ./
COPY cmake/ cmake/
COPY contracts/ contracts/
COPY apps/backend/ apps/backend/
COPY scripts/ scripts/
COPY tools/ tools/
RUN cmake -S . -B build/backend -C build/release-deps/prefix/ffido-cache.cmake -DCMAKE_BUILD_TYPE=Release \
    && cmake --build build/backend --parallel 4
# Permission tests must run without root's ability to bypass filesystem modes.
RUN useradd --uid 10000 --user-group --no-create-home ffido-build \
    && chown -R ffido-build:ffido-build build/backend \
    && runuser -u ffido-build -- env FFIDO_TEST_HPT=/src/build/release-deps/prefix/bin/hpt \
        python3 scripts/release/check_ctest.py build/backend
ARG FFIDO_REVISION=0000000000000000000000000000000000000000
ARG FFIDO_VERSION=1.0.0
ARG FFIDO_TAG=local
ARG FFIDO_BUILD_NUMBER=1
ARG FFIDO_STABLE=false
RUN python3 -c 'import json,sys; from pathlib import Path; Path("build/identity.json").write_text(json.dumps(dict(sha=sys.argv[1],version=sys.argv[2],tag=sys.argv[3],stable=json.loads(sys.argv[5]),build_number=int(sys.argv[4]))))' "$FFIDO_REVISION" "$FFIDO_VERSION" "$FFIDO_TAG" "$FFIDO_BUILD_NUMBER" "$FFIDO_STABLE" \
    && python3 scripts/release/package.py server linux x86_64 --identity build/identity.json \
    && mkdir /bundle && tar -xzf build/packages/*.tar.gz --strip-components=1 -C /bundle

FROM ubuntu:24.04@sha256:68ee22004a9109b44973313b02ff7b1de250f1de0f5ecb628d73f579aaff33ac
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates python3 libstdc++6 zlib1g \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid 10001 ffido && useradd --uid 10001 --gid 10001 --no-create-home ffido \
    && mkdir -p /var/lib/ffido /etc/ffido && chown 10001:10001 /var/lib/ffido
COPY --from=builder /bundle/ /opt/ffido/
RUN touch /opt/ffido/share/ffido/container-distribution
COPY apps/backend/config.container.example.json /opt/ffido/share/ffido/config.container.example.json
ARG FFIDO_REVISION=0000000000000000000000000000000000000000
ARG FFIDO_VERSION=1.0.0
ARG FFIDO_TAG=local
LABEL org.opencontainers.image.source="https://github.com/hashev/ffido" \
      org.opencontainers.image.revision="$FFIDO_REVISION" \
      org.opencontainers.image.version="$FFIDO_TAG" \
      org.opencontainers.image.licenses="MIT" \
      io.github.hashev.ffido.third-party-notices="/opt/ffido/legal/THIRD_PARTY_NOTICES.md"
ENV PATH="/opt/ffido/bin:${PATH}"
WORKDIR /var/lib/ffido
USER 10001:10001
EXPOSE 8080
STOPSIGNAL SIGTERM
ENTRYPOINT ["/opt/ffido/bin/fidoback"]
CMD ["/etc/ffido/config.json"]
