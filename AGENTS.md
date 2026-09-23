# MacPower

- Native application: Swift Package in `Sources/`, minimum macOS 14. `prototype/` is the approved browser design reference, not the shipping app.
- Follow selected Power Path layout and `docs/appearance.md`: system/light/dark, default system, saved preference. Native status icon remains a monochrome template.
- Distinguish adapter capability, actual DC input, signed battery power, and system load. Missing is never zero; estimates and data sources must remain visible.
- Read-only monitoring. No charging control, root helper, automatic login registration, or automatic notification permission requests.
- Keep collected hardware identifiers out of logs, exports and fixtures. Store local history in Application Support/MacPower only.
- Run `zsh scripts/test.sh` and `zsh scripts/build-app.sh` before native handoff. The test script handles the Swift Testing macro path in Command Line Tools 6.4. Record actual device and UI verification separately from fixture coverage in `docs/native-acceptance.md`.
- Do not claim untested devices, hardware states, calibration or notarization are verified.
