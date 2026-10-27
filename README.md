# Inch Converter

iPhone app that converts between decimal inches, fractional inches and centimeters, with its own numpad.

## Using it

- **Tap a field** to select it. The first key you press replaces the whole number.
- **Hold a field** to edit it in place: a cursor appears (with a haptic tap) and follows your finger as you slide along the number. Keys go in at the cursor, and ⌫ deletes the character before it. Holding the field you are editing again moves the cursor without losing what you typed.
- **The other two fields follow every key** you type, so there is nothing to press to convert. On the way to `2 7/16` they briefly show `2 7/1` (9"); input that can't be read yet, such as `3 5/`, leaves them at the last value they could read.
- **=** ends typing and shows the field in full (`2.5` becomes `2.50`, `3 6/8` becomes `3 3/4`). During a sum, = shows the total.
- **⌫ (Delete)**: tap removes the character before the cursor, hold empties all three fields (during a sum: the length being typed, and the others go back to the subtotal).
- **Inches / Feet + in** sets how the two inch fields show the length: `63.25` and `63 1/4`, or `5' 3.25"` and `5' 3 1/4"`. Under a foot the feet are left out (`11 1/2"`).
- **1/8, 1/16, 1/32, 1/64** sets what the fraction field rounds to. 15.88" shows ≈ 15 7/8 at every precision, because 56/64 is the closest 64th and reduces to 7/8; the note shows what is left over.
- **≈** in front of any field means its figures are rounded (two decimals, or the fraction's precision), and the field's top line says by how much: `rounded 0.005" down`, `rounded 0.002 cm up`. Typing 3 5/64 shows ≈ 3.08 in (rounded 0.002" up) and ≈ 7.82 cm.

Both choices are remembered.

### Typing a fraction

In the fraction field the key left of `0` shows **Space** or **/**: the first press adds the space after the whole number, the next adds the fraction slash.

| Keys | Result |
| --- | --- |
| `3` Space `5` `/` `8` | 3 5/8 |
| `5` Space `/` `8` | 5/8 |
| `7` | 7 |

A fraction you type stays as typed (reduced, so `3 6/8` shows `3 3/4`) until the value or the precision changes.

### Adding and subtracting

The **+** and **−** keys are in the right-hand column; the line above the numpad shows the sum.

1. Type a length in any field and press **+** (or **−**). The fields show the subtotal; type the next length, in any field. While you type it, the other two fields show the subtotal with it.
2. **=** ends the sum: the three fields show the total, and the line ends with `= total`.
3. After a total, **+** or **−** carries on from it; typing a new number starts over. **Clear** on the sum line ends the sum.

Fractions stay exact: `3 5/8 + 2 7/16 + 1 1/4` gives `7 5/16`, even at 1/8. With a length typed in centimeters or as a decimal, the total's fraction is rounded to the precision, with its note, unless it lands exactly on it. The last 10 finished sums are kept, also after the app is closed. Swipe down on the sum line to go back through them, one at a time. Tapping it opens the tape: every kept sum, one length per line with its total, and the sum running now at the bottom; scroll up for older ones. **Done** at the bottom closes it; the small **Clear all** at the top empties the history. Tapping another field while typing a length drops that length from the subtotal.

### Typing feet

With **Feet + in** chosen, a **Feet** key sits left of =. It follows a whole number:

| Field | Keys | Result |
| --- | --- | --- |
| Feet and inches | `5` Feet `3` `.` `2` `5` | 5' 3.25" |
| Feet and inches, fraction | `5` Feet `3` Space `1` `/` `4` | 5' 3 1/4" |
| either | `6` `3` | 5' 3" (inches alone also work) |
| either | `5` Feet | 5' 0" |

## Look

The MateLabs "Scope" style (`docs/matelabs-visual-style.md` in Boom-And-Lav Sync): always dark, near-black indigo panels, a header band with the icon and an oscilloscope grid, figures in a fixed-width font, native controls. The accent comes from the icon's sun: `#FABA41`, with `#B8520A` for fills under white text (=, Done, the chosen segment).

## Installing on an iPhone

Requires Xcode 16 or later and iOS 17 or later on the phone.

1. Open `InchConverter.xcodeproj`. The **InchConverter** scheme is shared in the project, so it shows in the toolbar.
2. Signing uses team `KJP2572BS8` (the same as RepMate) and the bundle identifier `com.sm.InchConverter`, set in the project. Check them under the **InchConverter** target → **Signing & Capabilities** if Xcode reports a signing problem.
3. Connect the iPhone, select it as the run destination and press **Run** (⌘R).

## Code

- `InchConverter/Converter.swift`: conversion, feet, fraction rounding and parsing, the numpad editing rules with the cursor, the sum and its history. Uses only Foundation.
- `InchConverter/ContentView.swift`: the screen, fields (with the cursor), sum line and tape, and numpad.
- `InchConverter/Theme.swift`: colours, header band, panels.
