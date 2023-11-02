Scaffolding to build a static idevicerestore easily, since all the libraries
can be pretty daunting to source yourself.

Cross-compiling isn't tested, probably needs some work.

## Requirements

On the host

* musl w/ the `musl-gcc` wrapper
* Kernel headers to pilfer from (this should be done better)
* usual suspects: autoconf, automake, libtool, pkgconf

## Building

* Set `PREFIX` to a directory that'll hold the files prepared by each `make install`.
* Set `BUILD_DIR` to a directory that'll hold the tarballs, source, and build detritus.

Example:

```shell
PREFIX=/home/calvin/prefix BUILD_DIR=/home/calvin/build bash build.sh
```

Serve `$PREFIX/bin/idevicerestore` and `$PREFIX/bin/usbmuxd` with garnish.

## Usage

TODO: Figure out how to use the standalone usbmuxd. You want to use a new
usbmuxd as possible, as old ones might not support your device.
