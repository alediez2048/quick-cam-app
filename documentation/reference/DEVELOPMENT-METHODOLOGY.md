# Development Methodology — Quick Cam

## Documentation-First Approach

Every change follows a defined sequence:

```
PRD (what to build)
  → System Design (how it fits together)
    → Ticket Primers (scoped units of work)
      → Implementation (code changes)
        → Dev Log (record what happened)
```

Write the documentation before writing the code. Update documentation when the design changes.

## Architecture-Constrained Development

All code changes must align with the architecture defined in `documentation/architecture/system-design.md`. If a ticket requires an architectural change, update the system design document first.

Key constraints:
- MVVM + Services pattern
- Single responsibility per service
- Thin views, no business logic in the view layer
- CameraViewModel as the sole coordinator
- AVFoundation threading on sessionQueue, UI on MainActor

## Ticket Workflow

1. **Read the primer** — Understand goal, scope, prerequisites, and acceptance criteria
2. **Implement** — Write code that satisfies the acceptance criteria, staying within scope
3. **Build verify** — `xcodebuild build` with zero errors
4. **Smoke test** — Manual verification per `documentation/testing/TESTS.md`
5. **Update dev log** — Add entry to `documentation/tickets/DEV-LOG.md`
6. **Commit** — Conventional commit format (see below)

## Conventional Commits

```
<type>(scope): description
```

Types: `feat`, `refactor`, `fix`, `docs`, `test`, `chore`

Examples:
```
refactor(models): extract RecordedVideo and TimedCaption into Models/
refactor(services): decompose CameraManager into focused services
docs: add project documentation and ticket primers
```

## Principles

- **Small, reviewable changes** — Each ticket completable in a single session
- **Always compilable** — Project must build after every commit
- **No behavior changes during refactoring** — Refactor tickets preserve existing UX
- **Log everything** — Dev log is the project's memory
