<!--
Title: refactor(<app>): <change>, like "refactor(<app>): give each panel page its own file".
Leave out the scope when the change isn't one app's. The release notes skip refactor, so nothing
people using the app notice may change. If something does, this is a feat or a fix.

Delete any section below that doesn't apply, comments included.
-->

<!-- A sentence or two: what was in the way, and what this makes easier. -->

## What changed

<!-- The code changes a reviewer should know about: what moved, what was renamed or deleted,
and what owns what now. -->

## Judgment calls

<!-- Decisions a reviewer might make differently, and the alternatives you rejected and why. -->

## Testing

<!-- How you know nothing changed for people using the app: builds and tests (with the count),
and what you checked in the running app. Run an app that syncs against throwaway
folders, never its real files. End with what you didn't verify, so the reviewer knows what to
try by hand. -->

## After merging

<!-- Anything someone has to do once this is on main: a secret to set, a submodule to init. -->
