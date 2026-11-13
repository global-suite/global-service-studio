# Localization

The interface ships in **English** and **Spanish** from the first release. English is the base language.

Everything in the repository is in English: code, comments, documentation, commits, issues and pull requests. Only the strings shown to the user are translated.

## Rules

- **No hard-coded user-facing strings.** Every string shown in the interface goes through the localization system.
- **A pull request that adds or changes a string includes both languages.** If you do not speak Spanish, say so in the pull request and a maintainer will supply the translation before merging.
- **Use full sentences as keys' source text**, with a comment that tells the translator where the string appears.
- **Never build sentences by joining fragments.** Word order differs between languages. Use format placeholders.
- **Plurals use plural variations**, not `if count == 1`.
- **Dates, times and numbers use the system formatters**, never hand-built strings.
- **Leave room.** Spanish text is often 20 to 30 percent longer than English. Layouts must not clip or overlap.

## How it works

Strings live in `Localizable.strings` files inside `en.lproj` and `es.lproj`, under the `Resources` folder of each module (for example `Sources/GSSApp/Resources/`). The key is the English text, with a comment saying where the string appears. String Catalogs (`.xcstrings`) are not used because the command line build (`swift build`) copies them without compiling them, so lookups return the key; they can return when an Xcode project exists. The interface language is chosen in Settings (⌘,): System, English or Español; System, the default, follows the system language. A change applies the next time the app opens.

`GSSCore` contains no user-facing text. It reports errors as typed values, and the interface turns them into localized messages.

## Spanish style

- Neutral Latin American Spanish, understood across countries.
- Informal address (`tú`), consistent with macOS itself.
- Follow Apple's Spanish terminology for standard interface terms.
- Terms that churches commonly keep in English may stay in English when the Spanish alternative would confuse operators. Record each such choice in the glossary below.

## Glossary

Agreed translations are added here as they are decided, so the interface stays consistent.

| English | Spanish | Note |
|---|---|---|
| Playlist | Lista de reproducción | |
| Slide | Diapositiva | |
| Stage display | Pantalla de escenario | |
| Theme | Tema | |

## Adding a language

More languages are welcome once the first release is out. Open a feature request first: a language is accepted when someone commits to maintaining it.
