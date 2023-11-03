Scaffolding to build a static idevicerestore easily, since all the libraries can be pretty daunting to source yourself.

## Requirements

On the host

* A cross-compiler that can make binaries with a static libc
  * Check out musl.cc or the musl-gcc script from your distro (i.e. musl-tools on Debian)
* usual suspects: autoconf, automake, libtool, cmake, pkgconf

## Building

* Set `CC` and `LD` to your compiler
* Set `PREFIX` to a directory that'll hold the files prepared by each `make install`.
* Set `BUILD_DIR` to a directory that'll hold the tarballs, source, and build detritus.
* If cross-compiling, set `TARGET` to the build triplet.

Example for native musl build:

```shell
CC=musl-gcc LD=musl-gcc PREFIX=/home/calvin/prefix BUILD_DIR=/home/calvin/build bash build.sh
```

Example for cross-compile musl build:

```shell
TARGET=x86_64-linux-musl CC=x86_64-linux-musl-cc LD=x86_64-linux-musl-cc PREFIX=/home/calvin/prefix-amd64 BUILD_DIR=/home/calvin/build bash -x build.sh
```

Any packages will be automatically downloaded, or you can put them manually in `BUILD_DIR`.

Serve `$PREFIX/bin/idevicerestore` and `$PREFIX/sbin/usbmuxd` with garnish.

### Tips

* If you run into issues with i.e. `libatomic.la` being in a bogus directory, just blow away `.la` files from your toolchain. libtool is more of a hazard than a help on Linux.

## Usage

TODO: Figure out how to use the standalone usbmuxd. You want to use a new usbmuxd as possible, as old ones might not support your device.
