# cliche for Nix

This project packages [cliche](https://github.com/nbd-wtf/cliche) as a Nix
flake for deployment on Nix-based systems.

It also provides a convenience Dockerfile that creates an extremely lightweight
image containing only the cliche binary and its runtime dependencies.

## Nix usage

Build cliche with:

```sh
nix build .
```

The resulting binary is available at:

```text
result/bin/cliche
```

Cliche stores its data by default in `~/.config/cliche`. To use another data
directory:

```sh
./result/bin/cliche -Dcliche.datadir=/path/to/data
```

## Docker usage

Build the Docker image:

```sh
docker buildx build -t cliche .
```

Start cliche using a local `data` directory for persistent state:

```sh
docker run --init -it --rm -v "./data:/data" cliche -Dcliche.network=testnet
```

The container stores cliche data in `/data` and is otherwise intentionally
minimal. The image is based on the Nix-built runtime closure rather than a full
Linux distribution.

## Packaging improvements

This packaging includes several fixes and updates to the upstream cliche
build:

1. Updated Bitcoin blockchain checkpoints for both mainnet and testnet.
2. Updated Lightning graph synchronization nodes for both mainnet and testnet.
3. Fixed cliche's testnet configuration so the testnet graph synchronization
   parameters are selected when `cliche.network=testnet` is used.

The Lightning graph is synchronized over Lightning gossip-query connections;
the Bitcoin checkpoints are used by Immortan's Electrum blockchain subsystem.

## Configuration

Cliche accepts configuration through system properties and a `cliche.conf`
file in its data directory. For example:

```hocon
cliche {
  network = "mainnet"
  seed = "your twelve word mnemonic seed"
}
```

System properties take precedence over values in `cliche.conf`.

Supported networks include:

```text
mainnet
testnet
regtest
signet
```
