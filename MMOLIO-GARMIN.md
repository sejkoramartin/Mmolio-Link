# Mmolio Bridge and Mmolio DataField

The Garmin sender delivers the existing v1 packet (`v,g,t,m,s,q`) to two separate
applications on the selected watch:

| Application | Connect IQ application ID |
| --- | --- |
| Mmolio Bridge (existing) | `a1b2c3d4e5f647589a0b1c2d3e4f5061` |
| Mmolio DataField (optional) | `7ca56fd800634cab90f28d5e72be2e05` |

The Bridge ID, packet, measurement timestamp and source/trend mapping are unchanged.
Mmolio WatchFace continues to read the Bridge complication. Garmin does not permit
data fields to subscribe to complications, so the field receives its own copy of
the phone packet using foreground Communications (Connect IQ API 5.0 or later).

Delivery is serialized: Bridge first, then DataField, even if Bridge fails. Each
destination has its own duplicate/older-reading policy and retries after failure.
The existing Garmin status and last-sent time still describe Bridge. An absent or
inactive DataField is optional and cannot replace a successful Bridge status with
an error. Its failures go to the diagnostic log. The existing iOS background task
ends after both delivery callbacks, subject to the time allowed by iOS.

## Installation

1. Build and install xDrip from `feature/garmin-watch` with this change. An older
   xDrip sends only to Bridge, so installing the `.prg` alone is insufficient.
2. Install `MmolioDataField.prg` built for FR165 with Connect IQ SDK 9.2.0 from
   `sejkoramartin/MedProbe`, branch `feature/xdrip-garmin-complication`.
3. In the watch's chosen activity, add **Mmolio DataField** as a Connect IQ data
   field on a data screen. Leave xDrip's existing Garmin Watch connection enabled.
4. On first installation the field displays `NO DATA` until a new reading arrives
   while the field is running. It then retains the original measurement timestamp
   in local storage. Old measurements must display their age/stale state.

The field's units and stale limit are independent of Bridge's settings. Both default
to mmol/L and 15 minutes. No Fit data, alerts, sensor settings or activity controls
are changed by this integration.

Verify on hardware that several new readings arrive during an activity with the
iPhone locked, Bridge remains current afterwards, and loss of the phone connection
makes the data field visibly stale instead of leaving an apparently current value.

## Validation

`bash tests/garmin-delivery/run.sh` tests the actual routing/encoder code with controlled
asynchronous SDK results. The existing Garmin feature-branch GitHub Actions workflow
then compiles the entire iOS app without signing. This does not install it on an
iPhone or validate Bluetooth delivery. A signed iPhone build remains necessary.
