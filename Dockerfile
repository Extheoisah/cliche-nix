# builder
FROM nixos/nix:2.35.1 AS builder

COPY . /tmp/build
WORKDIR /tmp/build

# remove the outputHash for the dependencies derivation
RUN nix shell \
    --extra-experimental-features 'nix-command flakes' \
    nixpkgs#gnused -c sed -i '/outputHash/d' flake.nix

# build our environment
RUN nix \
    --extra-experimental-features "nix-command flakes" \
    --option filter-syscalls false \
    build

# copy the nix store closure into a directory; the nix store closure
# is the entire set of nix store values that we need for the build
RUN mkdir /tmp/nix-store-closure
RUN cp -R $(nix-store -qR result/) /tmp/nix-store-closure

# final image
FROM scratch

WORKDIR /app

# copy /nix/store
COPY --from=builder /tmp/nix-store-closure /nix/store
COPY --from=builder /tmp/build/result /app

VOLUME ["/data", "/tmp"]
ENTRYPOINT ["/app/bin/cliche", "-Dcliche.datadir=/data"]
