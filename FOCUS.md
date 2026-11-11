# Periphery Focus — AI-free-by-default focus filter

**Model: default-on, user-owned, reversible.** Fresh installs boot with AI
chatbots, AI code assistants, AI-first search engines, and homework-answer
mills blocked. The student can disable blocking — wholly, per category, or
temporarily — at any time, with one command. No enforcement, no password,
no lock-in. Focus is a commitment device, not a cage.

## How it blocks (two thin layers)

1. **DNS layer** — `periphery-focus` manages a marked section in `/etc/hosts`
   resolving listed hostnames to `0.0.0.0` / `::0`. Survives reboots (it's
   just a file), needs no daemon.
2. **Browser layer** — Firefox enterprise policy
   (`/etc/firefox/policies/policies.json`) sets the default search engine to
   DuckDuckGo (no AI Overviews) and locks off the built-in AI chatbot sidebar.

Explicitly out of scope: TLS interception, packet filtering, VPN/Tor
blocking, killing local-model processes. All are bypassable by a
root-holding CS student and would break legitimate work — see
**Limitations** below.

## Categories

| Category | Blocks | Deliberately left reachable |
|---|---|---|
| `chatbots` | ChatGPT, Claude, Gemini, Copilot Chat, Meta AI, Grok, DeepSeek, Perplexity, Poe, You.com, Phind, Mistral | — |
| `code-assistants` | Copilot / Cursor / Codeium / Windsurf / Tabnine / Supermaven service endpoints | `github.com` itself, GitLab, package registries |
| `ai-search` | Perplexity, You.com, Phind, Andi, Komo, Exa | Google/Bing/DuckDuckGo (default changed, not blocked) |
| `ai-tutors` | Chegg, Course Hero, Brainly, StuDocu, Numerade | docs, Stack Overflow, forums, tutorials, flashcards, datasets |

Lists are the source of truth:
`overlay/usr/share/periphery-focus/lists/*.txt`. `/etc/hosts` is generated —
never hand-edit the managed block.

## Commands

```bash
periphery-focus status              # what's on, how many hostnames, block present?
periphery-focus list                # categories + their domains
sudo periphery-focus on             # enable all (also repairs a damaged block)
sudo periphery-focus on chatbots    # enable just chatbots
sudo periphery-focus off ai-tutors  # allow homework mills, keep the rest
sudo periphery-focus off            # everything off, until you say otherwise
sudo periphery-focus off --for 30m  # everything off for 30 minutes, then auto-restore
```

`off --for` restores your previous category selection afterwards (systemd
transient timer, with a background-sleep fallback). Any manual `on`/`off`
cancels a pending re-enable. Caveat: a reboot during a timed-off leaves
blocking off — run `on` to restore.

## Build integration

- The script, lists, and Firefox policy ship in `overlay/` and land in the
  rootfs via `apply-overlay.sh` like everything else.
- `full-build.sh` runs `periphery-focus --root $ROOTFS on` right after the
  overlay step, so ISOs boot blocked. It also force-sets `755` on the
  installed script in case the checkout lost the git exec bit.
- Safety nets: a missing state file means "all categories on", and bare `on`
  regenerates the hosts block from scratch — a fresh system converges to
  blocked even if a step was skipped.

## Adding or removing a domain

1. Edit the right list in `overlay/usr/share/periphery-focus/lists/`
   (one domain per line, `#` comments allowed).
2. Apex entries auto-cover their `www.` host; **everything else is
   exact-hostname only** — `example.com` does not cover `api.example.com`,
   so list each hostname that must be blocked.
3. On a live system, run `sudo periphery-focus on <category>` to regenerate;
   in the repo, commit the list — the hosts block is generated, lists are truth.
4. Invalid lines are skipped with a warning, never fatal.

## Boot-test checklist

- [ ] Fresh install: `getent hosts chatgpt.com` returns `0.0.0.0`;
      `periphery-focus status` shows 4 categories on
- [ ] `github.com` still resolves (only assistant endpoints blocked)
- [ ] `sudo periphery-focus off --for 1m` → reachable, then blocked again
      after a minute
- [ ] `sudo periphery-focus off chatbots` → chatbots reachable, other
      categories still blocked
- [ ] Hand-delete the managed hosts block → `sudo periphery-focus on`
      restores it
- [ ] Firefox: default search is DuckDuckGo; AI chatbot sidebar unavailable
- [ ] `about:policies` in Firefox shows the Periphery policy as active

## Limitations (honest)

- **Exact hostnames.** New AI domains/subdomains need list updates; nothing
  auto-discovers them.
- **Bypassable by design.** DNS-over-HTTPS in another browser profile, VPNs,
  proxies, phone tethering, Tor, and USB-carried offline models all bypass a
  hosts file. Blocking those would mean intercepting TLS or policing the
  network — rejected as hostile to a learning machine the student owns.
- **Firefox policy path.** Ubuntu ships Firefox as a snap; verify
  `/etc/firefox/policies/policies.json` is honored on the target release
  (`about:policies`) during boot test. If the snap ignores it, the fallback
  is a `distribution/policies.json` next to the browser or a first-run
  `user.js` default — TBD after testing, not guessed here.
- **Reboot during timed-off** leaves blocking off (state is on disk, the
  timer is not). Documented, acceptable for v1.
