# XDchat - Plan Implementacji

## Podsumowanie
Natywna aplikacja macOS do czatowania ze znajomymi z funkcjami: wiadomości tekstowe, GIFy (Giphy), naklejki Apple, emoji. Dark/Light mode w stylu Messengera.

## Wymagania techniczne
- **Platforma:** macOS 15+ (Sequoia)
- **Framework UI:** SwiftUI
- **Backend:** Firebase (Firestore + Auth)
- **API:** Giphy API dla GIFów

## Architektura

### Struktura projektu
```
XDchat/
├── XDchatApp.swift              # Entry point
├── Models/
│   ├── User.swift               # Model użytkownika
│   ├── Message.swift            # Model wiadomości
│   ├── Conversation.swift       # Model konwersacji (1-na-1, przygotowany na grupy)
│   └── Invitation.swift         # Model zaproszeń
├── Views/
│   ├── MainView.swift           # Główny widok (split view)
│   ├── Auth/
│   │   ├── LoginView.swift      # Logowanie
│   │   └── RegisterView.swift   # Rejestracja
│   ├── Conversations/
│   │   ├── ConversationListView.swift   # Lista rozmów (lewa strona)
│   │   └── ConversationRowView.swift    # Pojedynczy wiersz rozmowy
│   ├── Chat/
│   │   ├── ChatView.swift       # Widok czatu (prawa strona)
│   │   ├── MessageBubbleView.swift      # Bąbelek wiadomości
│   │   ├── MessageInputView.swift       # Pole do wpisywania
│   │   └── GiphyPickerView.swift        # Wybieranie GIFów
│   └── Admin/
│       ├── InviteUserView.swift         # Zapraszanie użytkowników
│       └── ManageUsersView.swift        # Zarządzanie (tylko admin)
├── Services/
│   ├── AuthService.swift        # Firebase Auth
│   ├── FirestoreService.swift   # Firebase Firestore
│   ├── GiphyService.swift       # Giphy API
│   └── InvitationService.swift  # System zaproszeń
├── ViewModels/
│   ├── AuthViewModel.swift
│   ├── ConversationsViewModel.swift
│   ├── ChatViewModel.swift
│   └── InvitationViewModel.swift
└── Utilities/
    ├── Theme.swift              # Dark/Light mode
    └── Extensions.swift         # Pomocnicze rozszerzenia
```

## Fazy implementacji

### Faza 1: Projekt i konfiguracja
1. Utworzenie projektu Xcode (macOS App, SwiftUI)
2. Dodanie Firebase SDK przez Swift Package Manager
3. Konfiguracja Firebase (GoogleService-Info.plist)
4. Struktura folderów

### Faza 2: Autentykacja
1. Model `User` (id, email, displayName, isAdmin, invitedBy, canInvite)
2. `AuthService` - rejestracja, logowanie, wylogowanie
3. `LoginView` i `RegisterView`
4. Przechowywanie stanu logowania

### Faza 3: System zaproszeń
1. Model `Invitation` (kod, createdBy, usedBy, isUsed)
2. Logika: tylko admin może zapraszać bez ograniczeń
3. Zaproszeni userzy mogą zapraszać innych (flaga `canInvite`)
4. Generowanie unikalnych kodów zaproszeniowych
5. Walidacja kodu przy rejestracji

### Faza 4: Lista konwersacji
1. Model `Conversation` (id, participants, lastMessage, updatedAt)
2. `ConversationListView` - lista po lewej stronie
3. Real-time sync z Firestore
4. Dodawanie nowej konwersacji ze znajomym

### Faza 5: Czat
1. Model `Message` (id, conversationId, senderId, content, type, timestamp)
2. Typy wiadomości: text, gif, sticker, emoji
3. `ChatView` z bąbelkami wiadomości
4. `MessageInputView` z polem tekstowym
5. Real-time sync wiadomości

### Faza 6: GIFy (Giphy)
1. `GiphyService` - wyszukiwanie i trending GIFy
2. `GiphyPickerView` - grid z GIFami
3. Przycisk GIF przy polu wiadomości
4. Wyświetlanie GIFów w bąbelkach

### Faza 7: Naklejki i Emoji
1. Integracja z `NSCharacterPickerTouchBarItem` lub custom emoji picker
2. Przycisk emoji/naklejki przy polu wiadomości
3. Renderowanie w wiadomościach

### Faza 8: Dark/Light Mode
1. `Theme.swift` - kolory, style
2. Automatyczne wykrywanie systemowego trybu
3. Opcja ręcznego przełączania
4. Style inspirowane Messengerem (gradient dla wysłanych wiadomości)

### Faza 9: Polish i UX
1. Animacje przejść
2. Powiadomienia o nowych wiadomościach
3. Status online/offline
4. Wskaźnik "pisze..."
5. Ikona aplikacji

## Schemat Firebase Firestore

```
users/
  {userId}/
    email: string
    displayName: string
    isAdmin: boolean
    invitedBy: string (userId)
    canInvite: boolean
    createdAt: timestamp

invitations/
  {invitationId}/
    code: string (unikalny 6-znakowy)
    createdBy: string (userId)
    usedBy: string? (userId)
    isUsed: boolean
    createdAt: timestamp

conversations/
  {conversationId}/
    participants: [userId, userId]
    lastMessage: string
    lastMessageAt: timestamp
    createdAt: timestamp

messages/
  {conversationId}/
    messages/
      {messageId}/
        senderId: string
        content: string
        type: "text" | "gif" | "sticker" | "emoji"
        gifUrl: string? (dla GIFów)
        timestamp: timestamp
```

## Wymagane zależności (Swift Package Manager)
- `firebase-ios-sdk` - Firebase Auth + Firestore
- `SDWebImageSwiftUI` - ładowanie GIFów
- `GiphyUISDK` lub własna integracja z Giphy API

## Setup Firebase i Giphy (na końcu)

### Firebase:
1. Wejdź na https://console.firebase.google.com
2. Utwórz nowy projekt "XDchat"
3. Dodaj aplikację Apple (macOS)
4. Pobierz `GoogleService-Info.plist`
5. Włącz Authentication > Email/Password
6. Utwórz Firestore Database (production mode)
7. Ustaw reguły bezpieczeństwa

### Giphy:
1. Wejdź na https://developers.giphy.com
2. Utwórz konto i aplikację
3. Skopiuj API Key

## Weryfikacja
1. Uruchom aplikację, zarejestruj się jako admin
2. Wygeneruj kod zaproszeniowy
3. Zarejestruj drugiego użytkownika z kodem
4. Rozpocznij rozmowę
5. Wyślij wiadomość tekstową
6. Wyślij GIF
7. Przetestuj Dark/Light mode
8. Sprawdź real-time sync (otwórz na dwóch komputerach)

## Uwagi
- Architektura przygotowana na grupy (Conversation ma `participants` jako tablicę)
- Pierwszy zarejestrowany user = admin
- Naklejki Apple wymagają użycia `NSSticker` API lub custom rozwiązania
