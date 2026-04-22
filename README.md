# dance-while-im-working

A tiny macOS menu-bar app: a little mascot that **dances when Claude Code is waiting on you** and **sleeps when it isn't**. Optionally, it can auto-press `Enter` so you never have to come back to the terminal just to answer a "Do you want to proceed?" prompt.

```
active   →  💃  (dancing in the menu bar)
idle     →  😴  (sleeping)
auto-yes →  dancer sends Return to your terminal whenever a prompt pops
```

## Why

Claude Code keeps asking permission mid-flow. If you trust what it's doing, you want a heads-up when it's stuck + a way to say "yes" from anywhere on your desk. This is that, You can scroll in peace now .

## Install

Two options — both zero-config.

### Option A — pre-built `.app` (recommended)

1. Grab the latest release: `DanceWhileImWorking.app.zip` from the [Releases](https://github.com/Chad-Mufasax/dance-while-im-working/releases) page.
2. Unzip → drag `DanceWhileImWorking.app` into `/Applications`.
3. Launch it. macOS will ask for **Accessibility permission** (System Settings → Privacy & Security → Accessibility). Grant it — that's how the app reads the terminal and sends the Enter key.
4. A 💃 / 😴 icon appears in your menu bar. That's it.

### Option B — build from source

```bash
git clone https://github.com/Chad-Mufasax/dance-while-im-working.git
cd dance-while-im-working
./scripts/build-app.sh
open dist/DanceWhileImWorking.app
```

Requires the Swift 5.9+ toolchain (ships with Xcode Command Line Tools on macOS 13+).

## Usage

Click the menu-bar icon for the menu:

- **Auto-press Enter** — toggle. When ON + dancing, the app posts a `Return` keystroke to the focused terminal whenever it detects a Claude Code prompt.
- **Pause detection** — freezes the mascot in "sleep" regardless of terminal state.
- **Quit** — quit.

## How it works

- Polls focused-window UI via the macOS Accessibility API (`AXUIElement`) every 500 ms.
- Matches the text pattern produced by Claude Code's permission prompts (`Do you want to proceed?`, numbered option list, `Yes` highlighted).
- When match → switch icon to dancing animation + (optionally) post a `kVK_Return` CGEvent to the frontmost process.
- When no match → icon returns to sleep.

No hook, no Claude config, no network. Everything is local.

## Permissions

macOS will prompt for **Accessibility** the first time you run it. This is required for both:
- reading the terminal window's text (to detect the prompt), and
- synthesising the Return keystroke.

If you revoke it later the app will just stay asleep forever.

## Safety note

Auto-pressing Enter means every permission prompt gets approved, including ones you might not want to approve. Use the toggle. You're the adult.

## License

MIT.
