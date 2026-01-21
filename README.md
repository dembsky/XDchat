# XDchat

Native macOS chat application built with SwiftUI and Firebase.

## Features

- Real-time messaging with text, GIFs, stickers, and emoji
- User authentication with invitation system
- Dark/Light mode with Messenger-inspired design
- Admin controls for user management
- Typing indicators and online status

## Requirements

- macOS 15.0+ (Sequoia)
- Xcode 16.0+
- Swift 5.9+
- Firebase account
- Giphy API key

## Setup Instructions

### 1. Create Xcode Project

1. Open Xcode and create a new project
2. Select **macOS** → **App**
3. Configure:
   - Product Name: `XDchat`
   - Team: Your team
   - Organization Identifier: Your identifier (e.g., `com.yourname`)
   - Interface: **SwiftUI**
   - Language: **Swift**
   - Storage: **None**
4. Save the project in the `/Users/dembsky/Documents/XDchat` directory (overwrite if prompted)

### 2. Add Source Files

After creating the project:
1. Delete the auto-generated `ContentView.swift` and any other default files
2. Drag the `XDchat` folder (with all Swift files) into the Xcode project navigator
3. Make sure "Copy items if needed" is unchecked and "Create groups" is selected

### 3. Add Dependencies via Swift Package Manager

1. In Xcode: **File** → **Add Package Dependencies...**
2. Add these packages:

**Firebase SDK:**
```
https://github.com/firebase/firebase-ios-sdk
```
- Select products: `FirebaseAuth`, `FirebaseFirestore`

**SDWebImageSwiftUI (for GIF support):**
```
https://github.com/SDWebImage/SDWebImageSwiftUI
```
- Select product: `SDWebImageSwiftUI`

### 4. Configure Firebase

1. Go to [Firebase Console](https://console.firebase.google.com)
2. Create a new project named "XDchat"
3. Add an Apple app:
   - Platform: macOS
   - Bundle ID: Your bundle identifier
4. Download `GoogleService-Info.plist`
5. Add it to the Xcode project (drag into the project navigator)

### 5. Enable Firebase Services

In Firebase Console:
1. **Authentication**:
   - Go to Authentication → Sign-in method
   - Enable **Email/Password**

2. **Firestore Database**:
   - Go to Firestore Database → Create Database
   - Start in **production mode**
   - Choose a location

3. **Firestore Security Rules**:
   Copy these rules in Firestore → Rules:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Users collection
    match /users/{userId} {
      allow read: if request.auth != null;
      allow write: if request.auth != null && request.auth.uid == userId;
    }

    // Invitations collection
    match /invitations/{invitationId} {
      allow read: if request.auth != null;
      allow create: if request.auth != null;
      allow update: if request.auth != null;
      allow delete: if request.auth != null &&
        get(/databases/$(database)/documents/invitations/$(invitationId)).data.createdBy == request.auth.uid;
    }

    // Conversations collection
    match /conversations/{conversationId} {
      allow read: if request.auth != null &&
        request.auth.uid in resource.data.participants;
      allow create: if request.auth != null;
      allow update: if request.auth != null &&
        request.auth.uid in resource.data.participants;

      // Messages subcollection
      match /messages/{messageId} {
        allow read: if request.auth != null &&
          request.auth.uid in get(/databases/$(database)/documents/conversations/$(conversationId)).data.participants;
        allow create: if request.auth != null &&
          request.auth.uid in get(/databases/$(database)/documents/conversations/$(conversationId)).data.participants;
      }
    }
  }
}
```

### 6. Configure Giphy API

1. Go to [Giphy Developers](https://developers.giphy.com)
2. Create an account and app
3. Copy your API key
4. In the app, go to **Settings** → **API Keys** → Enter your Giphy API key

### 7. Build Settings

Ensure these settings in your Xcode project:
- **Deployment Target**: macOS 15.0
- **Swift Language Version**: 5.9

### 8. Build and Run

1. Select your Mac as the run destination
2. Press **Cmd+R** to build and run

## First Run

1. **First user = Admin**: The first user to register becomes the admin
2. Register without an invitation code (only for the first user)
3. As admin, you can:
   - Invite other users by generating invitation codes
   - Grant/revoke invite permissions to other users
   - Manage all users

## Project Structure

```
XDchat/
├── XDchatApp.swift           # App entry point
├── Models/                    # Data models
│   ├── User.swift
│   ├── Message.swift
│   ├── Conversation.swift
│   └── Invitation.swift
├── Views/                     # SwiftUI views
│   ├── MainView.swift
│   ├── Auth/
│   ├── Conversations/
│   ├── Chat/
│   └── Admin/
├── ViewModels/               # View models (MVVM)
│   ├── AuthViewModel.swift
│   ├── ConversationsViewModel.swift
│   ├── ChatViewModel.swift
│   └── InvitationViewModel.swift
├── Services/                 # Backend services
│   ├── AuthService.swift
│   ├── FirestoreService.swift
│   ├── GiphyService.swift
│   └── InvitationService.swift
├── Utilities/                # Helpers
│   ├── Theme.swift
│   └── Extensions.swift
└── Resources/                # Assets
    ├── Assets.xcassets/
    ├── Info.plist
    └── Entitlements.entitlements
```

## Architecture

- **MVVM Pattern**: ViewModels manage state and business logic
- **Services Layer**: Singleton services handle Firebase and API communication
- **Real-time Updates**: Firestore listeners for live data sync
- **Theme System**: Adaptive colors for Dark/Light mode

## Troubleshooting

### Firebase not configured
Make sure `GoogleService-Info.plist` is added to your project and contains valid credentials.

### GIFs not loading
Check that your Giphy API key is configured in Settings.

### Authentication errors
Verify that Email/Password authentication is enabled in Firebase Console.

## License

This project is for educational purposes.
