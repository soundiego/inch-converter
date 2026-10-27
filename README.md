# Inch Converter

iPhone app that converts between decimal inches, fractional inches and centimeters, with its own numpad.

## Using it

- **Tap a field** to select it. The first key you press replaces the whole number.
- **Hold a field** to edit it. Keys are added to the end of the current number.
- **Enter** recalculates the other two fields. Input that can't be read (for example `3 5/`) puts the field back to its previous value.
- **Delete**: tap removes the last character, hold clears the whole number.
- **Fraction precision** (1/8, 1/16, 1/32, 1/64) sets what the fraction field rounds to. A `≈` in front of the fraction means it is rounded.

### Typing a fraction

In the fraction field the key next to `0` shows `␣` or `/`: the first press adds the space after the whole number, the second adds the fraction slash.

| Keys | Result |
| --- | --- |
| `3` `␣` `5` `/` `8` | 3 5/8 |
| `5` `␣` `/` `8` | 5/8 |
| `7` | 7 |

A fraction you type stays as typed (reduced, so `3 6/8` shows `3 3/4`) until the value or the precision changes.

## Installing on an iPhone

Requires Xcode 16 or later and iOS 17 or later on the phone.

1. Open `InchConverter.xcodeproj`.
2. Select the **InchConverter** target → **Signing & Capabilities** → choose your **Team**. If Xcode reports the bundle identifier `io.github.soundiego.InchConverter` is unavailable, change it to something unique.
3. Connect the iPhone, select it as the run destination and press **Run** (⌘R).

## Code

- `InchConverter/Converter.swift`: conversion, fraction rounding and parsing, and the numpad editing rules. Uses only Foundation.
- `InchConverter/ContentView.swift`: SwiftUI screen, fields and numpad.
