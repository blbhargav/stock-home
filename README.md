# StockHome

StockHome is a Flutter + Firebase app for tracking home groceries, shared by
everyone in the house. It lists all groceries with their status, purchase date,
and expiry date; highlights items that are expiring or expired; tracks what
needs to be purchased; and lets members mark items as purchased — all synced in
real time across the household.

> Note: the internal Dart package is still named `pantrypal` (unchanged to avoid
> touching platform build config). "StockHome" is the product/display name.

## Features
- Shared households: create one and invite members with a code, or join an existing one.
- Grocery inventory with category, quantity, and status
  (in stock / running low / needs purchase / purchased).
- Purchase date and expiry date tracking, with "expiring soon" and "expired" indicators.
- Shopping list of items that need to be purchased; swipe to mark purchased.
- Filters (All / In stock / To buy / Expiring soon / Expired) and search.
- Firebase Auth (email/password) + Cloud Firestore real-time sync.

## Getting started
See [FIREBASE_SETUP.md](FIREBASE_SETUP.md) to connect your Firebase project, then:

```bash
flutter pub get
flutter run
```

## Project structure
```
lib/
├── models/       Grocery item model, categories/units
├── services/     Firebase wrappers (auth, groceries, households)
├── providers/    App state (auth + groceries) via `provider`
├── screens/      Auth, household setup, home, grocery form
├── widgets/      Reusable grocery tile
├── theme/        Material 3 theme + status colors
└── main.dart
```
