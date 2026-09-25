# syntax=docker/dockerfile:1.7
#
# Commit-image Dockerfile (SMALL form) for daavoo/pyntcloud — builds ON TOP of the org base image
# (ghcr.io/mayhemheroes/base), which provides debian + clang/llvm + Python 3.13 + the build
# identities + the build-contract ENV.
#
# This is a Python (Atheris) target. The base has no PyPI deps, so we bake a WHEELHOUSE here (online,
# once) and mayhem/build.sh installs from it with --no-index — so the air-gapped PATCH re-run
# (docker run --network none ... bash mayhem/build.sh) never reaches the network (SPEC §6.5).
#
# Build (from the repo root):
#   DOCKER_BUILDKIT=1 docker build -f mayhem/Dockerfile \
#       --build-arg COMMIT=$(git rev-parse HEAD) -t pyntcloud-commit:test .

FROM ghcr.io/savantenvs/base:20260621

ARG COMMIT
ARG REPO_URL
# SOURCE_DATE_EPOCH stays an ARG (available to build.sh); never bake it as ENV — an empty value
# breaks clang. build.sh unsets it when empty.
ARG SOURCE_DATE_EPOCH
# Sanitizer override: declared WITHOUT a default so an unset arg lets the base ENV flow through.
ARG SANITIZER_FLAGS

# ── Bake the Python wheelhouse (ONLINE, root) so build.sh installs OFFLINE (air-gapped re-run) ──────
# atheris is the fuzzing engine; setuptools/setuptools_scm/wheel are pyntcloud's PEP-517 build
# backend; numpy/scipy/pandas are the core runtime; laspy/lazrs back the .las/.laz reader so that
# code path is fuzzed too.
ENV WHEELHOUSE=/opt/toolchains/python/wheelhouse
USER root
RUN mkdir -p "$WHEELHOUSE" && \
    python3 -m pip download --dest "$WHEELHOUSE" \
        'atheris==3.1.0' setuptools 'setuptools_scm>=6.3.1' wheel \
        numpy 'scipy>=1.6.0' pandas laspy lazrs && \
    chmod -R a+rX /opt/toolchains
USER mayhem

# Source enters from the build CONTEXT (the CI checkout): the FULL repo (incl. .git history) is
# copied to /mayhem; build.sh builds in place.
WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

RUN bash mayhem/build.sh

# Run the behavioral oracle at build time (a failing suite fails the image build).
RUN if [ -f mayhem/test.sh ]; then bash mayhem/test.sh; else echo "no mayhem/test.sh"; fi

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem
