A hackweek project of mine, currently in a very early state.

# Hawaii

A Luau packager built ontop of Lune!

## Building

This project can be built by installing lune, then running the command:

```
lune run .lune
```

For now, this runs a quickly put together build script that clones
`Packages\Hawaii.RuntimeBuilder\exports`, and then builds a debug `HWI` file.

The build script has several options that may help you configure how its built,
you can also enable EXE building, though this isn't that reliable as of current.

As this project develops, hopefully I'll be able to make it compile itself so
we dont need this.