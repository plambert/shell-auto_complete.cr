# Builds an image that runs shell-auto_complete's specs against one specific
# Crystal release. Driven by spec/run-crystal-versions.sh, which sweeps the
# Crystal version matrix to find the oldest release the shard still supports.
#
# Build context is the repository root (so the COPY paths below resolve), e.g.:
#   docker build -f spec/Dockerfile --build-arg CRYSTAL_VERSION=1.20.2 -t … .
ARG CRYSTAL_VERSION=latest
FROM crystallang/crystal:${CRYSTAL_VERSION}

WORKDIR /src

# shard.yml is required at compile time: src/shell-auto_complete.cr derives
# VERSION by shelling out to `shards version` against this directory. The lock
# is copied for completeness/reproducibility should dependencies ever be added.
# This shard currently has no dependencies, so `shards install` is intentionally
# omitted (it would only add a tooling failure mode unrelated to the compiler).
COPY shard.yml shard.lock ./

# Library source and the specs that exercise it.
COPY src/ src/
COPY spec/ spec/

# Default command runs the suite. The matrix script relies on the container's
# exit code (0 = pass) and reads the captured output via `docker logs`.
CMD ["crystal", "spec"]
