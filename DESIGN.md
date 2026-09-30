# Design guide

The rules every app in this repo follows. They sit on top of Apple's Human Interface Guidelines,
whose pages are in `.claude/skills/apple-design/references/hig`; where this guide is silent, the
HIG decides. Each rule names the page it comes from, or says it's our own call.

## Principles

- **One job, done in a glance.** An app's main surface does the one thing people opened it for.
  Everything else lives in menus. (`design-principles.md`, Purpose and Simplicity)
- **Native first.** System components, system colors, system type, standard shortcuts. People
  should never have to learn a control. (`branding.md`: "Express your brand with familiar
  components.")
- **The content carries the color.** Chrome stays monochrome; color belongs to what people made
  or chose. (`branding.md`: "Apply your app's accent color judiciously.")
- **One signature.** Each app gets a single thing it's remembered by, and everything around it
  stays quiet. Our call, after the skill's craft lens.

## Platform

- **macOS 14 and later.** Anything newer goes behind `if #available`, with a fallback that looks
  deliberate, not broken. Liquid Glass (macOS 26) falls back to the matching standard material.
- **Record the real SDK version in the binary.** SwiftPM stamps the deployment target as the SDK,
  which makes newer macOS run the app in compatibility mode, without its current look.
- **Light and dark, never an in-app appearance setting.** Check every change in both, and with
  Increase Contrast, Reduce Transparency, and Reduce Motion. (`dark-mode.md › Best practices`)

## Surfaces

- **Menu bar item.** An SF Symbol template image, no color. A click opens the main surface; a
  right-click or Control-click opens a menu with every command, ending in Settings… and Quit.
  (`the-menu-bar.md › Menu bar extras`)
- **Main surface.** A popover, or a borderless panel under the menu bar item, only as big as its
  content and no wider than 480 pt. (`popovers.md`: "Avoid making a popover too big.")
- **One layer of glass.** The surface itself is Liquid Glass on macOS 26 and the `.popover`
  material before it: corner radius 18 pt on glass, 12 pt on the material. Nothing inside it is
  glass: rows, cards, and fields never are. (`materials.md › Liquid Glass`: "Don't use Liquid
  Glass in the content layer.")
- **Paper for writing, material for glancing.** Editable documents sit on an opaque
  `textBackgroundColor`. Lists, status, and controls sit directly on the material. Our call.
- **Settings.** A grouped `Form` in a closable-only window titled "<App name> Settings", or a
  page in the main surface when the app has no windows. Either way ⌘, opens it, and it's in the
  app menu and the menu bar item's menu. (`settings.md › Desktop (macOS)`)
- **Every command is in the main menu,** with standard shortcuts, even though a menu bar app never
  shows it: AppKit routes key equivalents through it. (`the-menu-bar.md › Best practices`)
- **Save as you go.** A surface that closes when people click elsewhere never loses what they
  typed. Only an explicit Back, Cancel, or Esc discards an edit. (`popovers.md`: "Always save work
  when automatically closing a nonmodal popover.")

## Layout

Everything sits on a 4 pt grid.

| Token | Value | Use |
| --- | --- | --- |
| Edge inset | 16 pt | From the surface's edge to its text and controls, in bars, lists, and forms |
| Row inset | 8 pt | Inside a row, between its hover highlight and its content |
| Related spacing | 8 pt | Between controls or lines that belong together |
| Group spacing | 16 pt | Between groups; add a hairline `Divider` only between regions |
| Row radius | 10 pt | Hover and selection highlights |
| Document margin | 28 pt | Around editable text; lines stop at about 52 × the font size |

- **Regions, top to bottom:** a header (title, then the primary action at the trailing edge),
  the content, then a footer for status and secondary controls. Dividers separate regions, not
  rows. (`layout.md › Visual hierarchy`: "Group related items…")
- **Align to one leading edge.** Titles, row content, notices, and footer text all start at the
  edge inset. (`layout.md`: "Align elements to make them easier to scan…")

## Type

Use the system text styles, not point sizes. macOS has no Dynamic Type, but the styles keep one
scale across apps. (`typography.md › macOS built-in text styles`)

| Role | SwiftUI | Size |
| --- | --- | --- |
| The number that is the content | `.system(.title2, design: .rounded, weight: .semibold)` | 17 pt |
| Page and section titles | `.headline` | 13 pt bold |
| Names, body, form rows in windows | `.body` | 13 pt |
| Controls and text in compact surfaces | `.callout` | 12 pt |
| Captions, status, hints | `.subheadline` | 11 pt |

- **Nothing below 11 pt** that people need to read; 10 pt is the platform's floor and stays
  unused. (`typography.md › Ensuring legibility`)
- **Regular, medium, semibold, and bold only.** No light or thin weights, in text or symbols.
  (`typography.md`: "In general, avoid light font weights.")
- **Numbers that change get `.monospacedDigit()`,** so they don't jitter.
- **Personality lives in the content's numbers,** in SF Pro Rounded. Everything else is SF Pro.
  Documents use the font and size people pick, 14 pt by default. Our call.

## Color

- **Semantic colors only:** `labelColor` and its secondary and tertiary levels, `separatorColor`,
  `textBackgroundColor`, `quaternarySystemFill` for wells and code, and the system accent. Never a
  hard-coded system color value. (`color.md › System colors`)
- **The accent means "you can act here":** the prominent button, checkboxes, links, the caret,
  selection. Nothing else uses it. (`color.md`: "Avoid using the same color to mean different
  things.")
- **People's colors stay in the content:** their items' symbols, rings, bars, and numbers. They
  never tint chrome or controls.
- **Stored colors map to dynamic system colors** when they match one, so they follow the
  appearance and Increase Contrast. (`dark-mode.md › Dark Mode colors`)
- **Fill and ink.** Each content color has a *fill*, the color itself for swatches and 16% washes,
  and an *ink* for text, symbols, rings, and bars. Ink is the fill, darkened in light mode or
  lightened in dark mode until it reaches 4.5:1 against the surface; with Increase Contrast the
  system's high-contrast variants come first. Semibold isn't bold enough to earn the 3:1
  allowance. (`accessibility.md › Vision`)
- **Warnings and errors:** the text stays `labelColor` or secondary, next to an orange
  (warning) or red (error) symbol. Small orange or yellow text is never legible enough.
- **Destructive actions** use the destructive role, which makes them red.

## Controls

- **One control size per surface:** `.small` in compact surfaces, `.regular` in windows.
- **At most one prominent button per surface,** for the most likely action, bound to Return or
  ⌘Return. (`buttons.md › Style`)
- **Icon-only buttons** use an SF Symbol and `Button(_:systemImage:)` with `.labelStyle(.iconOnly)`,
  so VoiceOver has a name. Their hit area is at least 24 × 24 pt in compact surfaces (the platform
  minimum is 20 × 20, the default 28 × 28), and a tooltip names the action and its shortcut.
  (`accessibility.md › Mobility`; `buttons.md › Content`)
- **Custom clickable things** get a hover highlight (primary at 7% opacity, row radius), a press
  state, the button accessibility trait, and a default accessibility action.
  (`buttons.md`: "Always include a press state for a custom button.")
- **Choices over typing:** pickers, date fields, swatches. A swatch names its color for VoiceOver
  and in its tooltip, and shows selection with a ring, not by color alone. (`color.md › Inclusive
  color`)

## Feedback

- **Status lives in the interface:** a footer label, or an inline notice above the content.
  Alerts are for things that can't wait. (`feedback.md › Best practices`)
- **A notice** is a symbol, one or two lines of `.callout` text, and at most two small buttons
  (for example Show and OK). It says what happened and what, if anything, to do.
- **Confirm quietly:** a small label for about 1.5 s, like "Copied", then gone.
- **Empty states** are one sentence and the button that fills them. (`writing.md`: "Provide clear
  next steps on any blank screens.")

## Motion

- **0.1 to 0.25 s, easing out.** Surfaces fade in, sliding at most 8 pt; they fade out faster than
  they arrive. Frequent interactions get no motion beyond the system's own. (`motion.md › Best
  practices`)
- **Reduce Motion means fades only:** no sliding, no animated moves or resizes.
- **Motion never carries meaning on its own,** and nothing waits for an animation to finish.

## Writing

- **Title case** for buttons, menu items, window titles, and picker options. **Sentence case** for
  checkbox and toggle labels, descriptions, notices, and errors. (`menus.md › Labels`;
  `writing.md › Best practices`)
- **Buttons are verbs and name their object:** "Delete Photo", "Copy All". An ellipsis (…)
  marks anything that asks for more before it acts, wherever the command appears. (`menus.md`;
  `buttons.md › Push buttons`)
- **Errors say what happened and what to do.** No "we", no "oops", no apology. (`writing.md`)
- **Name what people see,** like "On this Mac" or "iCloud Drive › Folder", never how it's built.

## Before shipping a UI change

1. Review it with the apple-design skill, against this guide.
2. Look at it in light, dark, and Increase Contrast.
3. Tab through it with Full Keyboard Access, and read it with VoiceOver: every control has a name.
4. Turn on Reduce Motion and Reduce Transparency.
5. If the app supports macOS 14 or 15, look at the pre-Liquid Glass fallback too.
