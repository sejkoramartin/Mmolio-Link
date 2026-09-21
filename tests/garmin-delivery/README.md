# Mmolio delivery tests

Run `bash tests/garmin-delivery/run.sh` with a Swift toolchain. The harness compiles
the real `GarminModels.swift` (including `GarminDeliveryQueue` and the wire encoder).
Only the glucose snapshot input and asynchronous SDK send boundary are fixtures.
No phone, signing key, Connect IQ SDK or app launch is needed.

The feature-branch workflow runs this before compiling the complete iOS app against
the real Connect IQ SDK. The harness checks delivery ordering, independent retries,
duplicate/older suppression, callback lifetime, selection changes and failure
isolation. Device Bluetooth/background behavior still needs an iPhone and Garmin.
