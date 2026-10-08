# Colima Manager

A lightweight native macOS app for managing Docker Compose projects and local Docker resources through Colima.

## Build and launch

Requires macOS 13 or later, Xcode command-line tools, Colima, and Docker CLI with the Compose plugin.

```sh
./scripts/build-app.sh
open dist/ColimaManager.app
```

The app explicitly uses Docker context `colima`; it does not start Docker Desktop or manage the Colima VM lifecycle.
