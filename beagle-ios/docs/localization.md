# Localization

The five Xcode app and extension targets each own a `Localizable.xcstrings`
catalog under `BeagleSuite/Sources/<Target>/`. String extraction is enabled in
Xcode and in `project.yml`, so regenerating the project preserves the setup.
English is the catalog source language, consistent with the package's existing
default localization. Existing English and Portuguese literals are preserved;
this setup does not yet provide complete translations into either language.

## Translation workflow

1. Build the target in Xcode to extract localizable literals into its catalog.
   Build Watch and VisionOS with their own schemes; build extensions with their
   host app when they are included in the selected destination.
2. Open the target's catalog and add the desired language in Xcode. Review the
   source text, especially existing Portuguese literals, before translating.
3. Translate entries, add plural variations where needed, and review context.
4. Run using the scheme's Application Language and Application Region options.
   Check long text, accessibility labels, plural counts, dates, and numbers.
5. Commit the updated catalogs together with changes to localizable source text.

## Writing localizable text

SwiftUI literals such as `Text("Settings")` and `Button("Cancel")` are extracted
automatically. For UI text stored in a `String` property or passed to UIKit, use
`String(localized: "Settings", comment: "Title of the settings screen")`.
Passing an ordinary String variable to `Text` does not make it localizable.
Custom view APIs should accept `LocalizedStringKey` or `LocalizedStringResource`
when their argument represents a localizable label.

Keep complete sentences together and use interpolation instead of concatenation.
Use catalog plural variations and locale-aware format styles for counts, dates,
and measurements. Do not translate backend identifiers, URLs, model identifiers,
user messages, or generated conversation content.

Permission descriptions and other localizable bundle metadata need a separate
`InfoPlist.xcstrings` catalog when those translations are added. Shared Swift
package UI also needs its own processed catalog resource and explicit
`bundle: .module` lookups; the app catalog does not automatically extract strings
from package targets. These are follow-up translation coverage tasks.

Reference: [Apple's string catalog guide](https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog).
