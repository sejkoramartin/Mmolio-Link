# Mmolio Link

Mmolio Link is a focused iPhone CGM companion based on [xDrip4iOS](https://github.com/JohanDegraeve/xdripswift). It keeps xDrip4iOS sensor connectivity, follower data sources, and sharing services, while presenting a simpler Home screen: current glucose, trend, reading age, source, and history graph. The main tabs are Home, Devices, and Settings. Treatments and Statistics are not shown in the main navigation.

The app, its widgets, and the bundled Apple Watch views are intended for Czech users and ship Czech as their only interface localization. New upstream text must be translated before release; `python3 scripts/check-czech-localization.py` checks key and format-argument coverage.

The existing xDrip4iOS bundle identifiers, app group, data model, and Garmin wire format remain unchanged. A signed Mmolio Link build is intended to install as an update over the current xDrip4iOS build from the same Apple developer team, preserving stored data and sensor pairing. **Back up your data before the first migration.** A build signed with another team cannot replace the installed app.

## Data sources and watches

Master mode supports the sensor families implemented upstream, including Dexcom G6/G7/ONE/ONE+/Stelo, compatible Libre setups, and Medtrum. Follower mode retains Nightscout, Dexcom Share, LibreLinkUp, CareLink, Shared Calendar, and Medtrum EasyView. Availability depends on device, region, and upstream support.

The existing Garmin integration sends glucose, trend, and reading time to Mmolio Bridge and Mmolio DataField. Mmolio WatchFace continues reading the bridge complication. Support for other watch brands can be added behind a shared watch-delivery interface; it is not implemented yet.

## Build and releases

The `main` branch is checked by GitHub Actions with an unsigned iOS build and the Garmin/G7 compatibility tests. The TestFlight workflow is manual and needs the same six signing secrets used by the existing xDrip4iOS fork: `TEAMID`, `GH_PAT`, `FASTLANE_KEY_ID`, `FASTLANE_ISSUER_ID`, `FASTLANE_KEY`, and `MATCH_PASSWORD`. Secrets are scoped to repositories and are not copied automatically.

The current project still includes upstream internal code for Treatments, Statistics, and other services. Keeping those internals during the first UI migration protects sensor communication, history, data persistence, follower mode, and upgrades. Code can be removed later only after its dependencies have been traced and migration tested.

To update from upstream, merge changes from `JohanDegraeve/xdripswift` into a review branch and rerun the unsigned build and Garmin/G7 tests before merging to `main`. Preserve the bundle identifiers, persistence model, Garmin wire format, and user-visible Mmolio Link layout.

## Attribution and license

Mmolio Link is a derivative of xDrip4iOS by Johan Degraeve and contributors and is distributed under the [GNU GPL v3.0](LICENSE). The original [documentation](https://xdrip4ios.readthedocs.io/) remains useful for sensor compatibility and setup. This is experimental software, not an approved medical device; confirm readings with approved equipment before treatment decisions.

This derivative was first modified for Mmolio Link on 23 September 2026. The original copyright notices remain in the source files. Recipients of a binary should use the source commit associated with its build to obtain the corresponding source, build scripts, and license.
