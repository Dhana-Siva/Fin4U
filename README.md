# Fin4U

An iPhone app that scans receipts, itemizes them with Claude, and tracks personal
spending and shared expenses (split with a roommate) on the phone.

- `ios/` — SwiftUI + SwiftData app (iOS 17). Project generated with XcodeGen from `project.yml`.
  Copy `Secrets.example.xcconfig` to `Secrets.xcconfig` and fill in the backend URL and app key.
- `backend/` — small FastAPI service that sends a receipt image to Claude and returns structured
  items. It stores nothing. Needs `ANTHROPIC_API_KEY` and `APP_API_KEY` in its environment.
- `docs/` — the privacy policy, published with GitHub Pages.

Privacy policy: https://dhana-siva.github.io/Fin4U/
