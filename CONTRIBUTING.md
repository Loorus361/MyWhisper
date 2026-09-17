<!-- Describes a minimal contribution and verification workflow. -->
# Contributing

Start with a small, focused change. Discuss substantial behavior changes before implementing them. Read `AGENTS.md` and the relevant source files.

Use a separate branch and describe the problem, resulting behavior, checks run, and remaining limitations in your pull request. Clearly identify AI-assisted work and review it before submission.

## Verification

```sh
swift build
swift test
```

Use synthetic data. Never commit personal histories, bookmark exports, credentials, signing material or local application data. For user-interface or OS-integration changes, explain the manual checks performed and distinguish them from unit-test results.

Bug reports should include OS version, application/plugin version, reproduction steps and expected versus actual behavior. Remove private data from logs and screenshots.

This is a small personal project. Response times and feature requests are not guaranteed.
