# BOZ Modern iOS

Private compatibility packaging for the owner's supplied BOZ 1.3.5 IPA. This is not a reconstruction of the original game source.

Upload the original IPA to the `source-input` release, named `boz-v1.3.5.ipa`. Expected SHA-256: `b7eba04a7ccf957a7530e65164b33f6cb7151827160de37ff11b775f6cef332d`.

Run Actions → Build unsigned BOZ → Run workflow. The macOS runner fetches repair commit `de2574afbe3ff7811989f3fb4b38da373049ef0a` from https://github.com/Producdevity/cod-boz-ios, installs ipsw, extracts the legacy runtime from Apple firmware, compiles the fullscreen shim, and packages an ARM64 unsigned IPA.

The upstream patch redirects multiplayer to a community server. Server availability, physical-device gameplay, and signing/import through LiveContainer are not verified by package checks. HUD may overlap display cutouts. No signing identity, pairing file, or developer certificate is required for this build.

Output: `BOZ-Modern-iOS-unsigned.ipa` and SHA-256 in the workflow artifact. The artifact is a transport ZIP; the app inside remains an IPA. Unsigned output requires signing or a compatible container before launching.
