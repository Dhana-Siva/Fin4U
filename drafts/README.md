# Release drafts (not published)

`privacy-policy-with-splitwise.html` is the privacy policy updated for the
Splitwise feature. It is deliberately NOT in `docs/` (which GitHub Pages
publishes), so pushing other changes can't expose text about a feature that
hasn't shipped.

When the Splitwise build is ready to go to TestFlight:
1. Replace `[date this version is released]` with the real date.
2. `cp drafts/privacy-policy-with-splitwise.html docs/index.html`
3. Commit and push, then upload the build.
