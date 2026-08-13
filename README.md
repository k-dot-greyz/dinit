# dinit

macOS machine hydrate for Cursor + modern web dev: Homebrew, PATH, Python 3.14, browser GitHub auth, dev-master clone.

Territory ritual (fetch, env-doctor, crawl) lives in [dev-master](https://github.com/k-dot-greyz/dev-master) — run `./dinit.sh` there after hydrate.

## Quick start

```bash
dinit          # resume machine hydrate (or territory ritual when inside dev-master)
dinit auth     # browser GitHub login + persistent git credentials
dinit sitrep   # compact tool check
dinit clone    # auth + clone dev-master
```

Install hooks: run `dinit` once; it writes `~/.zshenv` / `~/.zshrc` entries for PATH and the `dinit()` wrapper.
