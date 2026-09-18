# Legal documents for App Store submission

Two PDFs, typeset from LaTeX, for Tactura's App Store listing:

| File | Pages | Where it goes |
|---|---|---|
| `PrivacyPolicy.pdf` | 6 | **Required.** App Store Connect → App Privacy → *Privacy Policy URL*. Host the PDF (or an HTML version of it) at a public URL. |
| `TermsAndConditions.pdf` | 8 | Optional but recommended. App Store Connect → App Information → *License Agreement* → "Custom" (or link it as an EULA URL). Also worth linking from inside the app. |

Both are built from `.tex` sources so the wording stays reviewable in git and
the PDF stays derived, not hand-edited.

## Fill these in before you submit

Every placeholder is rendered in **orange brackets** in the PDF, so they are
impossible to miss on a read-through. Search the `.tex` files for `\ph{`.

- [ ] `DEVELOPER LEGAL NAME` — the entity that will appear as the App Store
      seller. Must match your App Store Connect legal entity.
- [ ] `EFFECTIVE DATE` — the date you publish. Same date in both documents.
- [ ] `CONTACT EMAIL` — a monitored address. Required by GDPR and UU PDP.
- [ ] `POSTAL ADDRESS` — required for a GDPR-facing policy.
- [ ] `SUPPORT URL` — must match the Support URL in App Store Connect.
- [ ] `EU / UK REPRESENTATIVE` (Privacy Policy §10) — needed only if you are
      established outside the EU/UK *and* you monitor or target EU/UK users.
      Since Tactura collects nothing, an Art. 27 representative is very likely
      **not** required. Delete the line if so.
- [ ] `GOVERNING JURISDICTION` (Terms §15) — e.g. "the Republic of Indonesia".
- [ ] `CURRENCY AND AMOUNT` (Terms §10) — the liability cap. For a free app,
      a small nominal figure is conventional.
- [ ] `CONFIRM LOCATION` (Terms §12) — where third-party licence texts live in
      the app. If there is no Acknowledgements screen yet, either add one or
      change the sentence to point at a URL.

## App Store Connect: App Privacy answers

The documents assert **Data Not Collected**. To answer the questionnaire
consistently, select *"No, we do not collect data from this app"* — this is
accurate: the app has no networking code, no analytics SDK and no account
system, so no data is collected, linked or used for tracking.

## Rebuilding

```sh
make          # rebuild both PDFs
make clean    # remove LaTeX aux files
```

`tactura-legal.sty` holds the shared styling — fonts, the brand palette taken
from `Tactura/DesignSystem/Theme.swift`, the callout boxes and the placeholder
macro. Change it once and both documents follow.

Requires MacTeX (`xelatex`). The fonts used — Charter and Helvetica Neue — ship
with macOS.

## Bundled model licence

Tactura ships Apple's Core ML release of Depth Anything V2 Small under the
Apache License 2.0. Keep its licence and attribution with the other third-party
notices. The licence permits commercial use, subject to its notice and licence
requirements.
