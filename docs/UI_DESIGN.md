# UI design

## Visual direction

A premium, calm AI assistant. The UI is mostly light and air, with color
only where it means something:

- a warm off-white canvas with two very faint blue and lavender light sources
  near the top (`AmbientBackground`). They are static, so they cost no battery.
- one signature element, the **orb**: a softly glowing blue → lavender
  sphere that represents the assistant and shows its state (idle, thinking,
  listening).
- large rounded, floating surfaces (the composer, the New chat pill) with low,
  wide shadows instead of borders everywhere.
- assistant replies are part of the page, not bubbles. Only the user's
  messages get a quiet filled bubble.
- no AppBar, no bottom navigation, no card around each item.

It is iOS-inspired but stays natural on Android. It uses the platform
typeface, the platform page transitions and the platform back gestures.

## Palette

Raw values live in `AppColors`. Widgets read semantic tokens from
`AppPalette`, a `ThemeExtension`, through `context.palette`.

| Token | Value | Use |
| --- | --- | --- |
| `background` | `#F7F6F3` ivory | Canvas |
| `surface` | `#FFFFFF` | Composer, chips, sheets |
| `surfaceMuted` | `#F0EFEB` | Disabled send, secondary buttons |
| `hairline` | `#E7E5E0` | Separators and borders |
| `textPrimary` | `#14161F` ink | Body and titles |
| `textSecondary` | `#636775` slate | Previews, timestamps, captions (≈5:1 on the canvas) |
| `textTertiary` | `#8E919C` fog | Placeholder hints only |
| `accent` | `#5B7CFA` periwinkle | Primary action, cursor, orb |
| `accentSecondary` | `#9B87F5` lavender | Gradient partner |
| `userBubble` | `#EBEEF9` | User messages |
| `ambientPrimary` / `ambientSecondary` | `#DCE5FF` / `#EBE3FF` | Background glow, orb |
| `danger` / `dangerSurface` | `#D9434A` / `#FBE9E9` | Delete |

`accentGradient` (accent → lavender, top-left → bottom-right) is used only
on the send and finish buttons, the streaming caret and the orb.

**Dark mode:** add `AppPalette.dark` and `AppTheme.dark()`, then set
`darkTheme`. Widgets don't change.

## Typography

Platform typeface: SF Pro on iOS, Roboto on Android. This avoids bundling
fonts and keeps the app offline.

| Style | Size / weight | Use |
| --- | --- | --- |
| `displaySmall` | 30 / 600, −0.6 tracking | "How can I help?" |
| `titleLarge` | 20 / 600 | Screen title (History) |
| `titleMedium` | 17 / 600 | Header identity, empty-state title |
| `titleSmall` | 15.5 / 600 | Conversation titles |
| `bodyLarge` | 16 / 400, 1.55 line height | Messages, composer |
| `bodyMedium` | 15 / 400 | Secondary copy |
| `bodySmall` | 13.5 / 400 | Previews |
| `labelLarge` | 14.5 / 500 | Chips, buttons |
| `labelMedium` / `labelSmall` | 12.5 / 11.5, 500 | Timestamps, captions |

All text scales with the system setting. Layouts are tested at 1.6× on a
320 × 568 screen.

## Spacing, radius, shadows, sizes

- **Spacing (`AppSpacing`)** is a 4-pt scale: 2, 4, 8, 12, 16, 20, 24, 32, 48.
  The page gutter is 20. Content is capped at 720 px wide and centred on
  tablets and in landscape (`ContentWidth`).
- **Radius (`AppRadius`)**: sm 10, md 16 (tiles, sheets' buttons), lg 22
  (user bubble, 8 on the tail corner), xl 28 (composer, sheets), pill.
- **Shadows (`AppShadows`)**:
  - `floating`: 7% at a 28 px blur, plus a 4% contact shadow.
  - `floatingRaised`: used when the composer is focused.
  - `soft`: used on chips.
  - `accentGlow`: a 30% accent glow under gradient buttons.
- **Sizes (`AppSizes`)**: touch target ≥ 44, icon buttons 44, send 38 visual
  inside a 44 hit area, composer up to 6 lines.

## Motion

Durations come from `AppDurations`: fast 140 ms (press), medium 240 ms
(control state), slow 380 ms (layout changes) and entrance 720 ms (staggered
welcome). The curves are easeOutCubic, easeOutQuart for entering and
easeInCubic for exiting.

| Moment | Animation |
| --- | --- |
| Welcome screen | Staggered fade and 14 px lift: orb, then greeting, then chips |
| Empty → conversation | `AnimatedSwitcher` cross-fade |
| New message | One-time fade and 12 px lift (`EntryAnimation`). Messages that were already on screen or loaded from history don't animate. The finished reply replaces the streaming one in place, with no second entrance |
| Thinking | Three dots with staggered bounce, and the avatar orb switches to its faster "thinking" cycle |
| Streaming | Text grows chunk by chunk with a pulsing gradient caret at the end |
| Composer focus | Border tints to the accent and the shadow deepens (`AnimatedContainer`) |
| Send availability | Muted, scaled to 0.92 → gradient at full size with a glow; stop control (ink, square icon) while generating |
| Text ↔ voice | Height morphs (`AnimatedSize`) and content cross-fades with a 0.97 → 1 scale |
| Listening | Orb emits two expanding, fading rings |
| Transcribing | Orb switches to thinking mode and the actions fade out |
| Chip or pill press | Scale to 0.96 |
| History delete | Swipe: `Dismissible` slide and resize. Long-press: the row collapses and fades before removal |
| Screens | Cupertino transitions on iOS, predictive back / fade-forwards on Android |
| New chat button | Fades and scales in only once there is a conversation to leave |

**Reduce Motion:** `context.reduceMotion`
(`MediaQuery.disableAnimationsOf`) stops the orb, the dots and the caret,
skips entrance animations and makes layout changes instant.

## Components

- **ChatHeader**: history button (left), orb, "Halo" and "On-device
  assistant" (centre), and a New chat button (right) that keeps its space
  when hidden so the title stays centred.
- **ChatEmptyState**: hero orb, title, subtitle and suggestion chips. It
  scrolls if it doesn't fit (small phones, large text, keyboard open).
- **SuggestionChips**: white pills with a hairline border, soft shadow and a
  small accent icon. Tapping one sends its prompt.
- **MessageList**: a reversed `ListView`, so it stays pinned to the latest
  message while streaming and when the keyboard opens, and keeps the user's
  position if they scrolled up. The top and bottom edges fade under the
  header and composer. A timestamp divider appears only at the start of the
  conversation and after gaps of an hour or more.
- **UserMessageBubble**: right-aligned, filled with `userBubble`, at most 82%
  of the width.
- **AssistantMessage**: small orb and "Halo" label, then full-width text. It
  shows thinking dots until the first token arrives.
- **ChatComposer**: a floating white surface with a 28 radius.
  - Text mode: `[mic] Ask anything… [send]`.
  - Voice mode: `[cancel] (orb + Listening…) [finish]`.
  - It respects safe areas, the keyboard and Android gesture insets.
- **History**:
  - Header: back button, "History" and a search toggle.
  - Tiles: title, one-line preview and a relative date ("Today",
    "Yesterday", a weekday, then "Mar 4"), separated by hairlines. The open
    conversation is marked with a small accent dot.
  - Delete: swipe left, long-press (confirmation sheet), or the "Delete"
    accessibility action.
  - A floating ink "New chat" pill sits at the bottom.
  - Empty state: a small static orb, a title and one line of text.

## Accessibility

- Icon buttons have tooltips and semantic labels. Custom pressables are
  exposed as buttons.
- Status changes (Listening, Transcribing, Thinking, the streaming reply)
  are live regions.
- History rows offer a "Delete" custom semantics action, because swiping
  isn't discoverable with a screen reader.
- Touch targets are at least 44 pt. Secondary text meets ≈5:1 contrast.
