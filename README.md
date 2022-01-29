# protozig

Ideally, this will be a complete implementation of [protobuf](https://developers.google.com/protocol-buffers/docs/overview)
in [Zig](https://ziglang.org).

Initially, my focus will be entirely on a standalone protobuf to Zig translator. The syntax version I'll be focusing
on will be `proto3` (in the future, happy to add the previous `proto2` version too).

## How to...

You will need at least [Zig v0.9.0](https://ziglang.org/download/) in your path. Alternatively, if you can use
Nix, simply enter a new shell in the repo's root:

```
$ nix-shell
```

Building the `protozig` proto-to-zig translator:

```
$ zig build install
```

Running tests:

```
$ zig build test
```

