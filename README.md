# Colima Manager

A lightweight native macOS app for managing Docker Compose projects and local Docker resources through Colima.

## What it manages

- **Stacks:** list Compose projects, start, stop, and remove their containers.
- **Containers:** list, start, stop, restart, and remove individual containers.
- **Images:** inspect local tags, size, and container usage; remove unused images.
- **Volumes:** inspect project ownership and container usage; remove unused volumes.
- **Networks:** inspect attached containers; remove unused networks.

Stack removal opens a review sheet. Related project-owned networks and volumes are optional and unchecked by default. Resources used by containers outside the selected stack and resources declared external in Compose are kept. Optional cleanup is hidden if the current Compose config cannot be checked. Docker stops running containers with its configured grace period and may force-terminate one if that period expires. Removing an individual container preserves its volumes, and Compose files on disk are never deleted.

The app fetches the selected tab on demand and after actions. It does not run a background daemon or polling loop.

## Build and launch

Requires macOS 13 or later, Xcode command-line tools, Colima, and Docker CLI with the Compose plugin.

```sh
./scripts/build-app.sh
open dist/ColimaManager.app
```

The app explicitly uses Docker context `colima`; it does not start Docker Desktop or manage the Colima VM lifecycle.
