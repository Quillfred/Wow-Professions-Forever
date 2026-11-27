# SkillRoute Forever: working notes

## Every change
- Run `lua5.1 tests/test_planner.lua`, `lua5.1 tests/smoke_wow.lua` and `tools/check_globals.sh`.
- Commit and push, then send a test build with `tools/devzip.sh <scratchpad>`. It is named
  `<next version>-dev.N`.
- Add each change to the top `## <next> (not released yet)` section of CHANGELOG.md. Never
  add it to a section that has already been released. This section is the list of what is
  waiting to go out.

## When to release to CurseForge
The owner tests dev builds in game, while friends get CurseForge releases. A release is
worth it when one of these holds:

1. **Hotfix: release the same day.** A bug that:
   - costs gold, e.g. buying twice or paying the wrong price
   - loses data or settings
   - throws Lua errors
   - makes the route wrong in a way players will follow, e.g. a missing step, a wrong
     trainer, or a recipe that can't be learned
2. **Batch: release when the batch is ready.** This covers everything else: wording,
   layout, new options and features. Release once both are true:
   - a meaningful set has built up: about 3 or more user-visible changes, or one notable
     feature
   - every change touching buying, gold or saved data has been checked in game by the
     owner
   Aim for at most about one batch release a week.
3. **Never release:** buying or gold code that hasn't been tried in game, or the middle of
   a change the owner is still giving feedback on.

When the owner says "push to CurseForge", look at the unreleased changelog section first.
If it is a small, untested or still-in-progress batch, say so in one line and recommend
waiting. If they still want it released, release it. When a batch meets the rules above,
suggest releasing it unprompted, and list what's in it.

## Releasing
- Bump `## Version` in SkillRoute/SkillRoute.toc and rename the changelog heading to the
  version.
- Run all checks, commit and push.
- Dispatch the release:
  `gh api -X POST repos/Quillfred/Wow-Professions-Forever/actions/workflows/release.yml/dispatches -f ref=main -f 'inputs[tag]=vX.Y.Z'`
- Monitor the run through the API, then report the result and the time per step.

## Don't
- Copy Disenchantry's or Mastercraft's code or data. Their licences forbid it; use facts
  only, with credit.
- Commit SavedVariables or other files from the owner's WoW folder.
- Use `git stash`. The auto-mode classifier denies it.
- Put the CurseForge token anywhere except the CF_API_KEY GitHub secret.
