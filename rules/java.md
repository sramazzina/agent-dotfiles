---
paths: ["**/*.java", "**/pom.xml"]
---
# Java / Maven

Applies Rules 9 and 16 to Java projects.

- Verify each task commit locally with `mvn -pl <module> -am -DskipITs verify` (Surefire unit tests).
- Testcontainers ITs need a Docker socket and may only be runnable on CI. That is the case where opening the PR earlier (Rule 16, step 1) is justified.
