# Validation for the upstream contribution

Automated checks run with `python Updater/run_checks.py`. They cover Python updater failures and rollback, release packaging, Lua 5.1 syntax, the existing compatibility scenarios, audit regression scenarios and full-database simulated rendering. `lupa` is only a development dependency; alternatively install a Lua 5.1 interpreter. No live network updater run or in-game test is implied by these checks.

The WoW simulation cannot reproduce engine-enforced secret values, secure execution/taint, XML templates or actual rendering. Its dropdown library is a stub. Validate those in the target client before merging or releasing. The API shapes were checked against the Forever branch of Blizzard UI source, not assumed from Retail.

## Manual checks in Forever

- [ ] Fresh installation of the locally built ZIP with no external libraries: addon loads, defaults are English, collection is on, options open without Lua errors.
- [ ] Fight an NPC such as the Wind Spike caster. No Damage Meter reads occur in combat. After combat, an unambiguous enemy-session ID is used, its spell appears once, and Attack remains hidden. Also check a caster that is not selected when combat ends.
- [ ] Fight or encounter different NPC IDs with equal names. Ambiguous session names are skipped; historical data never follows a new target.
- [ ] A caster absent from the enemy roster produces a skip message rather than a guessed identity. Reset the Damage Meter and verify pending work is cleared.
- [ ] Disable collection before queued work runs: no new observation is stored, the disabled hint appears, and re-enabling resumes on new session updates.
- [ ] Verify tooltip, target frame and both display locations. Check every extra field in title/separate modes, all hotkey modes, and instance hiding. Same-name spells with different details remain distinguishable.
- [ ] Verify Spanish and Chinese options/text, available client metadata, language changes and English fallback. Check that Chinese glyphs render.
- [ ] `/nabdebug`, `/nabdebug clear`, X, Escape and dragging work.
- [ ] `/reload` and a full restart preserve valid settings and learned abilities without duplicate lines or collection listeners.
- [ ] Upgrade an existing NpcAbilitiesForever installation with SavedVariables retained. Old boolean observations migrate to records marked unverified; malformed partial entries do not break valid ones.
- [ ] Apply a documented NPC correction (including an explicit empty list), update the database and reload. Learned spells must not bypass it. Resetting that correction returns to baseline/learned data.
- [ ] On Classic 11509, ordinary display remains functional and Forever collection stays disabled. If testing Season of Discovery, compare its target-frame and tooltip spell lists.

## Submission scope

Push a development branch and open an upstream pull request. Do not create a release tag, GitHub Release or CurseForge upload as part of this review. The original license and author credit are retained. The manual checks above are pending until someone runs them in the actual game.
