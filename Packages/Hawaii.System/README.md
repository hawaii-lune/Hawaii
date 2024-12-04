# Hawaii.System

This defines logic for interfacing with the Bootstrapper's std exports (known as
the system). This is done to prevent duping of code across several packages in
the CLI project. This also contains the code to build the bootstrapper, however,
this may be directly inlined into the Builder moving forward.

The exports of this library are defined in `/src/init.luau`.