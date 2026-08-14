# dinit

macOS machine hydrate for Cursor + modern web dev: Homebrew, PATH, Python 3.14, browser GitHub auth, dev-master clone.

Territory ritual (fetch, env-doctor, crawl) lives in [dev-master](https://github.com/k-dot-greyz/dev-master) (private repo — requires GitHub access via `dinit auth`) — run `./dinit.sh` there after hydrate.

## Quick start

Fresh checkout — bootstrap once, then open a new shell:

```bash
./dinit.sh       # first run: installs shell hooks (needs a real terminal)
# open a new shell tab/window, then:
dinit            # resume machine hydrate (or territory ritual when inside dev-master)
dinit auth       # browser GitHub login + persistent git credentials
dinit sitrep     # compact tool check + hydrate catalog
dinit clone      # auth + clone dev-master
dinit env        # print export PATH=... for this tab
dinit purge-python  # pin python 3.14 + purge older brew/mise pythons
dinit skip gh    # persist skip for a skippable phase (gh, devmaster, shell)
dinit retry gh   # mark a phase pending for the next `dinit`
```

`dinit` is one verb: continue. Phases are cards in `lib/phases.json`. Required work must be `ok` or `skipped` before hydrate is complete; `sudo` is session-only and never counts. Transient failures (DNS, brew lock) retry in-process; human blockers (CLT, browser auth) park with a `next:` command.

Install hooks: `./dinit.sh` writes `~/.zshenv` / `~/.zshrc` entries for PATH and the `dinit()` wrapper. After that, use `dinit` in new shells.
