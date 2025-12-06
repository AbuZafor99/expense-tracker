# Expense Tracker App

A lightweight expense tracker app built with Flutter and Firebase.

## Features

- **Authentication**: Email/Password login and registration
- **Dashboard**: Real-time balance, income, and expense totals
- **Transactions**: Add, edit, and delete income/expense entries
- **Filtering**: Filter by category, search by name
- **Sorting**: Sort by date or amount
- **Real-time Sync**: All data synced via Cloud Firestore

## Setup Instructions

### 1. Install Dependencies
```bash
flutter pub get
```

### 2. Firebase Configuration

You need to set up Firebase for this project:

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Create a new project or use an existing one
3. Enable **Authentication** (Email/Password provider)
4. Enable **Cloud Firestore Database**
5. Download configuration files:
   - **Android**: Download `google-services.json` and place it in `android/app/`
   - **iOS**: Download `GoogleService-Info.plist` and place it in `ios/Runner/`

### 3. Run FlutterFire CLI (Optional but Recommended)

To automatically configure Firebase:
```bash
flutterfire configure
```

This will update `lib/firebase_options.dart` with your project's configuration.

### 4. Run the App
```bash
flutter run
```

## Project Structure

```
lib/
├── main.dart                # Entry point
├── firebase_options.dart    # Firebase configuration
└── screens/
    ├── login_screen.dart    # Auth service + Login/Register UI
    └── home_screen.dart     # Expense model + Controller + Dashboard UI + Bottom sheets
```

Each screen file contains:
- **Model**: Data structures
- **Controller**: Business logic (GetX)
- **UI**: All widgets and screens


## Usage

1. **Sign Up/Login**: Create an account or login
2. **Add Income**: Tap the green "Income" button
3. **Add Expense**: Tap the red "Expense" button
4. **Filter**: Use the category dropdown to filter transactions
5. **Search**: Type in the search bar to find specific entries
6. **Sort**: Use the sort dropdown to order by date or amount
7. **Delete**: Swipe left on any transaction to delete
8. **Edit**: Tap on a transaction to view details and edit

## Categories

**Expense Categories**: Food, Transport, Entertainment, Shopping, Bills, Other

**Income Categories**: Salary, Bonus, Investment, Other
