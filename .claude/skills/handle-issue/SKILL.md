---
name: handle-issue
description: Takes GitHub issues in this repo to open PRs, one issue-handler agent per issue, then reviews each PR and its CI. Use when asked to handle, fix or build issues by number, like "handle #31 and #32".
argument-hint: <issue> [<issue> ...]
---

Issues: $ARGUMENTS

1. Read each issue with `gh issue view <n>`, enough to know its app and whether it changes UI. The agents do the work, not you.
2. Make at most one agent the UI driver. Agents that post events or drive a running app through Accessibility close each other's panels and steal focus. The rest check UI with offscreen snapshots. This also applies to agents launched later in the session while one already drives.
3. Launch one `issue-handler` agent per issue, all in one message. Its prompt gives:
   - the issue number;
   - whether it's the UI driver;
   - anything the user said about the issue;
   - the commit and PR attribution lines from your instructions, which subagents don't get on their own.
4. As each agent reports, review its PR without redoing the work:
   - Read `gh pr diff <n>` and check that:
     - the fix sits where the cause is;
     - nothing changed outside the app's folder that CLAUDE.md doesn't allow;
     - README and `Info.plist`'s version are untouched;
     - no temporary test code was committed.
   - Wait for CI with `gh pr checks <n> --watch`. Send a problem or a CI failure back to that agent to fix on its branch.
5. Tell the user, for each PR: the link and title, what changed, the judgment calls they may want changed, and what to try by hand.
