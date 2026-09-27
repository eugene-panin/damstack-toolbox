FROM python:3.13.15-alpine3.24

ARG TARGETARCH
ARG TOFU_VERSION=1.12.6
ARG TOFU_SHA256_AMD64=5dc43da4f750f33873dc25e94587128709e819e544b7be9016b255316153c3a8
ARG TOFU_SHA256_ARM64=e573979ba68a17fe7b881752051a694a7efcd970e39521f6a25775197861ed4d
ARG CONFTEST_VERSION=0.70.1
ARG CONFTEST_SHA256_AMD64=613d124b8f6c1f3cee890491f7ab19114cca5a2102ca47cb2e6c35b4c23f9c8a
ARG CONFTEST_SHA256_ARM64=8eb914755cb1b3c610d557019d5f373d5528b366ba706961d1a23f2ec55eab57
ARG ANSIBLE_CORE_VERSION=2.21.4
ARG PYYAML_VERSION=6.0.3

RUN apk add --no-cache ca-certificates git openssh-client \
 && pip install --no-cache-dir "ansible-core==${ANSIBLE_CORE_VERSION}" "PyYAML==${PYYAML_VERSION}" \
 && case "${TARGETARCH}" in \
      amd64) tofu_sha="${TOFU_SHA256_AMD64}"; conftest_arch=x86_64; conftest_sha="${CONFTEST_SHA256_AMD64}" ;; \
      arm64) tofu_sha="${TOFU_SHA256_ARM64}"; conftest_arch=arm64; conftest_sha="${CONFTEST_SHA256_ARM64}" ;; \
      *) echo "no build for ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
 && cd /tmp \
 && wget -q "https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}/tofu_${TOFU_VERSION}_linux_${TARGETARCH}.zip" -O tofu.zip \
 && echo "${tofu_sha}  tofu.zip" | sha256sum -c - \
 && unzip -q tofu.zip tofu -d /usr/local/bin \
 && wget -q "https://github.com/open-policy-agent/conftest/releases/download/v${CONFTEST_VERSION}/conftest_${CONFTEST_VERSION}_Linux_${conftest_arch}.tar.gz" -O conftest.tar.gz \
 && echo "${conftest_sha}  conftest.tar.gz" | sha256sum -c - \
 && tar -xzf conftest.tar.gz -C /usr/local/bin conftest \
 && rm -f tofu.zip conftest.tar.gz \
 && mkdir -p /home/damstack /work \
 && chmod 1777 /home/damstack /work \
 && chmod 0666 /etc/passwd

COPY entrypoint /usr/local/bin/damstack-entrypoint

ENV HOME=/home/damstack \
    ANSIBLE_HOST_KEY_CHECKING=True \
    TF_IN_AUTOMATION=1
WORKDIR /work
ENTRYPOINT ["/usr/local/bin/damstack-entrypoint"]
CMD ["sh"]
