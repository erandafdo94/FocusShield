# Focus Shield for macOS

Focus Shield is a personal macOS study blocker. Save a list of distracting applications and website domains, then start a timed focus session.

Blocking is local and system-wide. It does not require a browser extension, browser developer mode, a paid Apple Developer membership, a VPN, or Accessibility permission.

## Install and start using it

1. Open `FocusShield.xcodeproj` in Xcode.
2. Select the **FocusShield** scheme and **My Mac** destination.
3. In the FocusShield target's **Signing & Capabilities** tab, choose **Sign to Run Locally** if Xcode asks for signing.
4. Press **Command-R** once to build and open the app.
5. For a stable installation, copy the built `FocusShield.app` into `/Applications` or `~/Applications` and open that copy.
6. Click **Install Helper**. macOS requests administrator approval once because website blocking updates `/etc/hosts`. Reinstall the helper after moving or replacing the app.

## Everyday use

1. Click **Choose Apps** and select applications from `/Applications`.
2. Add website domains such as `youtube.com`, `reddit.com`, or `x.com`.
3. Enter the number of hours to block—up to **24**, including decimals such as `1.5`—and click **Start Timer**. Once started, the timer cannot be stopped early.
4. Focus Shield asks selected running apps to quit and blocks each saved domain plus its `www` address across browsers and other apps. When a session starts with websites in the list, Chrome closes after the hosts-file update so it cannot reuse an existing connection; reopen it to continue with blocking active.
5. The block list is locked during focus, and blocking is removed automatically when the timer ends.

Your block list remains saved for the next session.

## Architecture

- The SwiftUI app edits the block list, displays focus state, and starts timed sessions.
- `FocusBlockManager` owns timed-session state.
- `FocusShieldAgent` runs as a per-user login agent to keep application blocking active after the main window closes.
- A second instance of `FocusShieldAgent` runs as a privileged launch daemon. It manages a clearly marked Focus Shield section in `/etc/hosts`, then flushes the macOS DNS cache whenever that section changes.
- State is stored as JSON at `~/Library/Application Support/FocusShield/state.json`.

The one-time helper setup creates:

- `~/Library/LaunchAgents/com.example.FocusShield.agent.plist`
- `/Library/PrivilegedHelperTools/com.example.FocusShield.hosts-agent`
- `/Library/LaunchDaemons/com.example.FocusShield.hosts-agent.plist`

## Honest limitations

- Application blocking is a graceful quit request. An app can refuse to terminate or show a save dialog.
- `/etc/hosts` has no wildcard support. Focus Shield blocks the exact saved domain and automatically adds its `www` address; add other subdomains explicitly when needed.
- A determined administrator can unload the helpers or edit `/etc/hosts`. This is a personal self-control tool, not parental-control software.

## Build verification

```sh
xcodebuild -project FocusShield.xcodeproj \
  -scheme FocusShield \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO build
```
