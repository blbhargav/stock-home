# StockHome — Firebase Setup

StockHome is a shared home grocery tracker. Before the app can run, connect it
to your own Firebase project. This is a one-time setup.

## 1. Create a Firebase project
1. Go to the [Firebase console](https://console.firebase.google.com/).
2. Click **Add project** and follow the prompts.

## 2. Enable the services StockHome uses
In the Firebase console for your project:
- **Authentication** → Sign-in method → enable **Email/Password**.
- **Firestore Database** → Create database → start in **production mode**.

## 3. Connect this Flutter app to Firebase
Install the FlutterFire CLI and run configure from the project root:

```bash
dart pub global activate flutterfire_cli
flutterfire configure
```

Select your Firebase project and the platforms you want (Android, iOS, etc.).
This **overwrites** `lib/firebase_options.dart` with your real keys and adds the
platform config files (e.g. `google-services.json`, `GoogleService-Info.plist`).

> The `lib/firebase_options.dart` currently in the repo is a placeholder with
> `REPLACE_ME` values so the project compiles. `flutterfire configure` replaces it.

## 4. Deploy Firestore security rules
The included `firestore.rules` restricts data so only members of a household can
read or write its groceries. Deploy it with the Firebase CLI:

```bash
npm install -g firebase-tools   # if not already installed
firebase login
firebase init firestore         # choose your project; use existing firestore.rules
firebase deploy --only firestore:rules
```

## 5. Run the app
```bash
flutter pub get
flutter run
```

## How sharing works
- The first person **creates a household** and gets a **household code**
  (visible under the account icon → "Household code", with a copy button).
- Everyone else **joins** using that code on the setup screen.
- All members then see and edit the same live grocery list in real time.

## Data model (Firestore)
```
users/{uid}                     -> { householdId }
households/{householdId}        -> { name, members: [uid...], createdAt }
households/{id}/groceries/{gid} -> {
    name, category, quantity, unit, status,
    purchaseDate, expiryDate, updatedBy, updatedAt
}
```

`status` is one of: `in_stock`, `running_low`, `needs_purchase`, `purchased`.

## Features
- List all home groceries with category, quantity, and status.
- Track **purchase date** and **expiry date**; see "expiring soon" and "expired".
- Mark items as **needs purchase** to build a shared **shopping list**.
- Mark items **purchased** (swipe on the shopping list) to move them back to stock.
- Filters: All / In stock / To buy / Expiring soon / Expired, plus search.
- Real-time sync across all household members via Firestore.
