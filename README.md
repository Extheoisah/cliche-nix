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

Cliche stores its data by default in `~/.config/cliche`, and reads
`~/.config/cliche/cliche.conf` from that directory. To use another data
directory:

```sh
./result/bin/cliche -Dcliche.datadir=/path/to/data
```

That flag also moves the config file to `/path/to/data/cliche.conf`. See
[Configuration](#configuration).

## Docker usage

Build the Docker image:

```sh
docker buildx build -t cliche .
```

Start cliche using a local `data` directory for persistent state:

```sh
docker run --init -it --rm -v "./data:/data" cliche -Dcliche.network=testnet
```

The container stores cliche data in `/data`. Put configuration in
`./data/cliche.conf` on the host; that file is `/data/cliche.conf` inside the
container. The image is based on the Nix-built runtime closure rather than a
full Linux distribution. See [Configuration](#configuration).

### Apple Silicon Mac

The image is `linux/amd64` only. The flake defines packages for
`x86_64-linux`, and the GraalVM native-image distribution pinned in
`flake.nix` is the x86_64 Linux build. Docker Desktop on an Apple Silicon Mac
builds `linux/arm64` containers by default, so the commands above fail before
compilation:

```text
error: flake 'path:/tmp/build' does not provide attribute
'packages.aarch64-linux.default' or 'defaultPackage.aarch64-linux'
```

Pass `linux/amd64` for both the build and the run. Docker runs that image
under emulation:

```sh
docker buildx build --platform linux/amd64 -t cliche .
```

```sh
docker run --platform linux/amd64 --init -it --rm \
  -v "./data:/data" cliche -Dcliche.network=testnet
```

Omitting `--platform` on `docker run` still starts the container, and Docker
prints:

```text
WARNING: The requested image's platform (linux/amd64) does not match the
detected host platform (linux/arm64/v8) and no specific platform was requested
```

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

Create `cliche.conf` in the data directory before starting cliche. Cliche
creates the directory on startup, then exits if `cliche.seed` is missing. When
that happens it prints a freshly generated 12-word mnemonic you can copy into
the file.

| How cliche is started | Config file |
| --- | --- |
| `cliche` | `~/.config/cliche/cliche.conf` |
| `cliche -Dcliche.datadir=/path/to/data` | `/path/to/data/cliche.conf` |
| `docker run -v "./data:/data" cliche` | `./data/cliche.conf` |

The file is [HOCON](https://github.com/lightbend/config/blob/main/HOCON.md).
These are the settings it controls, with their built-in defaults:

```hocon
cliche {
  network = "mainnet"
  seed = "your twelve word mnemonic seed"
  json.compact = false
  websocket {
    host = "127.0.0.1"
    port = 12000
  }
}
```

`seed` is required and must be a valid 12-word mnemonic. `network` is one of
`mainnet`, `testnet`, `regtest`, or `signet`.

The same keys can be set with `-D` flags. A flag overrides the value in
`cliche.conf`:

```sh
./result/bin/cliche -Dcliche.datadir=/path/to/data -Dcliche.network=testnet
```

Two settings are read from the command line. `-Dcliche.datadir` chooses the
data directory, and therefore where `cliche.conf` is loaded from.
`-Dcliche.electrum=host:port` selects a single Electrum server, for example
`-Dcliche.electrum=electrum.blockstream.info:50001`. Without that flag, cliche
uses its built-in server list for the selected network.
