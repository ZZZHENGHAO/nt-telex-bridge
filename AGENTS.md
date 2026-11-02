# Scope and isolation

- Work only in this independent project and `ZZZHENGHAO/nt-telex-bridge`.
- Do not read or write the user's `nt-disperser` working copy as part of this project.
- Never modify that repository's code, branches, Issues, PRs, Actions, or automations.
- Lua only. Do not flash or modify TXi firmware without a separate user request.
- Keep protocol evidence pinned to upstream commits. Distinguish source verification,
  desktop simulation, and real NT/TXi measurements.
- Run `lua tests/test.lua` with Lua 5.4 from this repository before publishing changes.
- Hardware I2C access is untested until the user records the result in docs/HARDWARE_TEST.md.
