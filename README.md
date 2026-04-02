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
