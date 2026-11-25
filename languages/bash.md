# Bash

Applies Rules 9 and 16 to Bash projects.

- Verify each task commit locally with the project's bats suite (through the project's test runner, if it has one) and `shellcheck` on the changed scripts.
- Entry-point scripts start with `set -euo pipefail`. Library files are source-only: sourcing one has no side effects and does not change shell options.
- Do not hard-code absolute paths. Resolve the project root once from the script location (`$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)`) and build all paths from it.
- Make external commands substitutable through an environment variable, so tests can run against host binaries or stubs instead of containers or the network.
