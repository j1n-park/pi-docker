# Pi Agent Docker

A small experiment for running Pi Agent inside a local Docker sandbox.

Goals:

- keep Pi tools and caches out of the host project
- mount the current project into the container
- make it easy to reset the container environment when it gets messy

This starts as a zsh wrapper plus a Dockerfile. More lifecycle commands will be
added as the workflow settles.

## First image

Build locally:

```sh
docker build -t pi-agent-sandbox:base .
```

Source `pi.zsh` and run `pi` from a project directory. The first pass just uses
`docker run --rm`; state persistence still needs work.

The wrapper now tags a `current` image and commits the container after each run,
so the Pi install and package caches survive between sessions.

Before every run, the wrapper makes a timestamped snapshot tag such as
`pi-agent-sandbox:snap-20260405-160000`. Rollback commands are still manual for
now.

The project is mounted below `/workspace/<repo-name>` instead of directly at
`/workspace`. That keeps resumed sessions scoped to the project path.
