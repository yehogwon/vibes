<!--
Title: fix(<app>): <change>, like "fix(<app>): open an item when its row is clicked". Leave out
the scope when the change isn't one app's. The release notes list the change after the colon
under Fixes, so say what works now.

Delete any section below that doesn't apply, comments included.
-->

<!-- A sentence or two: what people saw before this, and what they should have seen. -->

## Cause

<!-- Why it happened, down to the line or API that caused it. -->

## What changed

<!-- What someone using the app will notice, then the code changes a reviewer should know about.
A table works well when the behavior differs by case. -->

## Judgment calls

<!-- Decisions a reviewer might make differently, and the alternatives you rejected and why. -->

## Design review

<!-- UI changes only: the apple-design skill's findings against DESIGN.md, each with its severity
and whether it was fixed or accepted, citing the HIG page it comes from. -->

## Testing

<!-- What you ran and what it showed: builds and tests (with the count), the test that fails
without the fix, and how you checked the bug is gone in the running app. Run an app that
syncs against throwaway folders, never its real files. End with what you didn't verify, so the
reviewer knows what to try by hand. -->

## After merging

<!-- Anything someone has to do once this is on main: a secret to set, a submodule to init. -->
