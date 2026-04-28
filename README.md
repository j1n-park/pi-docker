# Pi Agent Docker

Run Pi Agent in Docker with a current image and timestamped snapshots.

This wrapper keeps system and tool state in Docker images while leaving project
changes in the host checkout through a bind mount. The Linux variant builds the
container user with the host uid/gid so edited files have the right ownership.

Install with `./install.sh`, then source either `pi.zsh` or `pi-linux.zsh`.
