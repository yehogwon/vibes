<!--
Title: build(<app>): <change>, like "build(<app>): record the real SDK version in the binary".
Leave out the scope when the change isn't one app's. The release notes skip build, so say in the
title what changes about building the app, not about using it.

Delete any section below that doesn't apply, comments included.
-->

<!-- A sentence or two: what was wrong with the build or the package, or what this adds. -->

## What changed

<!-- Changes to build.sh, Package.swift, Tools, or dependencies, and what they mean for the built
app: its architectures, deployment target, SDK version, or size. -->

## Judgment calls

<!-- Decisions a reviewer might make differently, and the alternatives you rejected and why. -->

## Testing

<!-- What you built and how you checked the result: `<app>/build.sh`, the tests (with the count),
what `lipo -info` or `vtool -show-build` reports, and that the app opens. End with what you
didn't verify. -->

## After merging

<!-- Anything someone has to do once this is on main: a secret to set, a submodule to init. -->
