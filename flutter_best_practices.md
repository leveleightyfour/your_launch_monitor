# Flutter Best Practices

A reference guide for consistent, maintainable Flutter development across all projects.

---

## Table of Contents

1. [Project Structure](#project-structure)
2. [Naming Conventions](#naming-conventions)
3. [Riverpod â Providers](#riverpod--providers)
4. [Riverpod â State & AsyncValue](#riverpod--state--asyncvalue)
5. [UI Architecture](#ui-architecture)
6. [Widget Design](#widget-design)
7. [Navigation](#navigation)
8. [Error Handling](#error-handling)
9. [Performance](#performance)
10. [Testing](#testing)
11. [General Dart](#general-dart)

---

## Project Structure

Organise by **feature**, not by type. Each feature folder is self-contained.

```
lib/
âââ core/
â   âââ constants/
â   âââ extensions/
â   âââ theme/
â   âââ utils/
âââ features/
â   âââ auth/
â   â   âââ data/          # Repositories, data sources, DTOs
â   â   âââ domain/        # Models, entities, interfaces
â   â   âââ application/   # Providers, notifiers, use-case logic
â   â   âââ presentation/  # Screens, widgets, controllers
â   âââ settings/
â       âââ data/
â       âââ domain/
â       âââ application/
â       âââ presentation/
âââ shared/
â   âââ widgets/           # App-wide reusable widgets
â   âââ providers/         # App-wide providers (e.g. router, theme)
âââ main.dart
```

- Keep `main.dart` minimal â bootstrap only (ProviderScope, app-level config).
- Do not put business logic in `presentation/`. That belongs in `application/`.
- `shared/` is for things used across 3+ features; otherwise keep it in the feature.

---

## Naming Conventions

| Thing               | Convention                                       | Example                    |
| ------------------- | ------------------------------------------------ | -------------------------- |
| Files               | `snake_case`                                     | `user_profile_screen.dart` |
| Classes             | `PascalCase`                                     | `UserProfileScreen`        |
| Variables / methods | `camelCase`                                      | `fetchUserProfile()`       |
| Constants           | `camelCase` (or `SCREAMING_SNAKE` for top-level) | `kDefaultPadding`          |
| Providers           | `camelCase` + `Provider` suffix                  | `userProfileProvider`      |
| Notifiers           | `PascalCase` + `Notifier` suffix                 | `UserProfileNotifier`      |
| State classes       | `PascalCase` + `State` suffix                    | `UserProfileState`         |
| Private members     | `_camelCase`                                     | `_isLoading`               |
| Enums               | `PascalCase` values                              | `LoadingStatus.idle`       |

---

## Riverpod â Providers

### Choose the right provider type

| Provider                | Use for                                                    |
| ----------------------- | ---------------------------------------------------------- |
| `Provider`              | Synchronous, read-only values (services, repos, constants) |
| `FutureProvider`        | Single async reads (config, one-time fetches)              |
| `StreamProvider`        | Continuous real-time data (sockets, Firestore streams)     |
| `NotifierProvider`      | Complex state with multiple mutations                      |
| `AsyncNotifierProvider` | Complex state that is also async                           |
| `StateProvider`         | Simple primitive state (a toggle, a selected index)        |

Prefer `NotifierProvider` / `AsyncNotifierProvider` over `StateNotifierProvider` (deprecated in Riverpod 2.x).

### Provider definition

```dart
// â Good â typed, scoped, named clearly
final userRepositoryProvider = Provider<UserRepository>((ref) {
  return UserRepository(client: ref.watch(httpClientProvider));
});

// â Good â AsyncNotifierProvider
final userProfileProvider =
    AsyncNotifierProvider<UserProfileNotifier, UserProfile>(
  UserProfileNotifier.new,
);
```

### Notifier structure

```dart
class UserProfileNotifier extends AsyncNotifier<UserProfile> {
  @override
  Future<UserProfile> build() async {
    // Initial load. Called on first watch and on ref.invalidate().
    return ref.watch(userRepositoryProvider).fetchProfile();
  }

  Future<void> updateDisplayName(String name) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(userRepositoryProvider).updateName(name),
    );
  }
}
```

- `build()` is the single source of truth for initial/reset state.
- Use `AsyncValue.guard()` to safely wrap async mutations.
- Never perform side effects directly in `build()` â use `ref.listenSelf` or `ref.listen` instead.

### Provider dependencies

```dart
// â Use ref.watch for reactive dependencies
final formattedNameProvider = Provider<String>((ref) {
  final profile = ref.watch(userProfileProvider).valueOrNull;
  return profile?.displayName ?? 'Guest';
});

// â Use ref.read inside callbacks/methods (not during build)
void onButtonTap() {
  ref.read(userProfileProvider.notifier).updateDisplayName('Aden');
}

// â Never use ref.watch inside callbacks or event handlers
void onButtonTap() {
  ref.watch(userProfileProvider); // BAD â causes unexpected rebuilds
}
```

### Auto-dispose

- Use `@riverpod` code generation with `keepAlive: false` (default) for providers that should clean up.
- Use `keepAlive: true` or `ref.keepAlive()` only for genuinely long-lived resources (auth state, global config).
- For feature-scoped providers, prefer auto-dispose to avoid memory leaks.

```dart
@riverpod
Future<List<Post>> posts(PostsRef ref) async {
  // Auto-disposed when no longer watched
  return ref.watch(postRepositoryProvider).fetchAll();
}
```

### Family providers

```dart
// â Use .family for parameterised providers
final postByIdProvider = FutureProvider.family<Post, String>((ref, id) {
  return ref.watch(postRepositoryProvider).fetchById(id);
});

// In widget:
final post = ref.watch(postByIdProvider('post-123'));
```

- Keep family parameters simple and serialisable (`String`, `int`, data class with `==` and `hashCode`).
- Avoid passing full model objects as family parameters.

---

## Riverpod â State & AsyncValue

### Handling AsyncValue in UI

```dart
// â Use .when for the full three-state pattern
ref.watch(userProfileProvider).when(
  data: (profile) => ProfileWidget(profile: profile),
  loading: () => const CircularProgressIndicator(),
  error: (e, st) => ErrorWidget(message: e.toString()),
);

// â Use skipLoadingOnRefresh to prevent flicker on pull-to-refresh
ref.watch(userProfileProvider).when(
  skipLoadingOnRefresh: true,  // keep showing data while refreshing
  data: (profile) => ProfileWidget(profile: profile),
  loading: () => const CircularProgressIndicator(),
  error: (e, st) => ErrorWidget(message: e.toString()),
);

// â Use .valueOrNull for optional reads where null is acceptable
final name = ref.watch(userProfileProvider).valueOrNull?.displayName;
```

### Avoid overusing AsyncValue

- Don't wrap purely synchronous, non-failing state in `AsyncValue`.
- For UI-local state (expanded, selected tab), use plain state classes or `StateProvider`.

### State classes (for Notifiers with multiple fields)

```dart
// â Use freezed or plain immutable classes
@freezed
class AuthState with _$AuthState {
  const factory AuthState({
    @Default(false) bool isLoading,
    User? user,
    String? errorMessage,
  }) = _AuthState;
}
```

- Always make state immutable â use `copyWith`, never mutate in place.
- Each distinct loading/error concern should be represented explicitly in the state.

---

## UI Architecture

### Screen â Controller pattern

```
Screen (ConsumerWidget)
  âââ watches providers, handles top-level layout
       âââ Child Widgets (pure or lightly connected)
            âââ delegate mutations back via notifier calls
```

- Screens are thin: they wire providers to widgets and handle navigation.
- Extract any widget over ~60 lines into its own file/class.
- Do not call `ref.read(provider.notifier).someMethod()` from deep inside the widget tree. Pass callbacks down instead.

### ConsumerWidget vs ConsumerStatefulWidget

```dart
// â Prefer ConsumerWidget when no local widget state is needed
class ProfileScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) { ... }
}

// â Use ConsumerStatefulWidget when you need initState/dispose
// e.g. AnimationController, TextEditingController, focus nodes
class SearchScreen extends ConsumerStatefulWidget {
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}
```

- Do not convert to `ConsumerStatefulWidget` just to store state that belongs in a provider.

### Listening to providers for side effects

```dart
// â Use ref.listen for navigation, snackbars, dialogs â NOT ref.watch
ref.listen<AsyncValue<void>>(submitFormProvider, (_, next) {
  next.whenOrNull(
    error: (e, _) => ScaffoldMessenger.of(context).showSnackBar(...),
    data: (_) => context.go('/success'),
  );
});
```

Never trigger navigation or show dialogs as a side effect of `build()`. Use `ref.listen`.

---

## Widget Design

### Composition over inheritance

- Build complex UIs from small, focused widgets rather than deeply nested build methods.
- Prefer extracting widgets as new classes over helper methods that return `Widget` (improves rebuilds and readability).

```dart
// â Extracted class â rebuilds independently
class AvatarWidget extends StatelessWidget { ... }

// â Helper method â always rebuilds with parent
Widget _buildAvatar() => CircleAvatar(...);
```

### const constructors

- Always use `const` where possible. It tells Flutter this widget subtree never changes.

```dart
const SizedBox(height: 16),
const Divider(),
const Text('Hello'),
```

### Layout principles

- Use `Expanded` and `Flexible` inside `Row`/`Column` only when you want the child to fill remaining space. Don't wrap everything in `Expanded` by default.
- Avoid `Expanded` inside a `ListView` or any unbounded parent.
- Prefer `SizedBox` over `Container` when only setting size (lighter widget).
- Use `Padding` as a wrapper rather than adding padding to Container where possible.

### Theme over hardcoded values

```dart
// â Use theme tokens
Text(
  'Hello',
  style: Theme.of(context).textTheme.titleMedium,
)

// â Avoid hardcoded colours / sizes in widget code
Text('Hello', style: TextStyle(fontSize: 18, color: Color(0xFF333333)))
```

- Define all colours, typography, spacing, and border radii in `ThemeData`.
- Use `ColorScheme` tokens (`primary`, `surface`, `onPrimary`, etc.) not raw hex values.

---

## Navigation

- Use a single, declarative router â **go_router** is the standard choice.
- Define all routes in a single file (`router.dart` or `app_router.dart`).
- Pass IDs/primitive values via path/query parameters, not full model objects.
- Keep navigation logic out of Notifiers â handle it in the UI layer via `ref.listen`.

```dart
// â Navigate via GoRouter
context.go('/profile/$userId');
context.push('/settings');

// â Avoid Navigator.of(context).push with MaterialPageRoute inline
```

---

## Error Handling

- Define a sealed `Failure` / `AppError` type for domain-level errors.
- Use `AsyncValue.guard()` in notifiers to safely capture exceptions into state.
- Never swallow errors silently â always log and surface them.
- Show user-facing errors in the UI, not raw exception messages.

```dart
// â Sealed error type
sealed class AppError {
  const AppError();
}
class NetworkError extends AppError { ... }
class AuthError extends AppError { ... }
class UnknownError extends AppError { ... }
```

---

## Performance

- Use `select` to narrow rebuilds to only the data a widget needs:

```dart
// â Only rebuilds when displayName changes, not the whole profile
final name = ref.watch(userProfileProvider.select((p) => p.valueOrNull?.displayName));
```

- Avoid creating objects (lists, maps, styles) inside `build()` â move them to constants or memoize.
- Use `ListView.builder` / `ListView.separated` for all lists of unknown length. Never `ListView` with `children:` for dynamic content.
- Profile with Flutter DevTools before optimising. Don't prematurely extract widgets based on intuition alone.
- Avoid large `Stack` hierarchies and excessive `Opacity` widgets (both are GPU-expensive).

---

## Testing

### Unit tests â Notifiers

```dart
test('updateDisplayName updates state correctly', () async {
  final container = ProviderContainer(overrides: [
    userRepositoryProvider.overrideWithValue(FakeUserRepository()),
  ]);
  addTearDown(container.dispose);

  final notifier = container.read(userProfileProvider.notifier);
  await notifier.updateDisplayName('Aden');

  expect(
    container.read(userProfileProvider).valueOrNull?.displayName,
    'Aden',
  );
});
```

- Override dependencies with fakes/mocks in `ProviderContainer`.
- Test notifier state transitions, not implementation details.

### Widget tests

- Use `ProviderScope` with `overrides` to inject test state.
- Test user-facing behaviour (text on screen, button presses), not internal widget structure.

### Integration tests

- Keep integration tests in `integration_test/`.
- Use `patrol` or `flutter_test` robot pattern for maintainable test steps.
- Target real devices or emulators; integration tests should mirror production conditions.

---

## General Dart

- Prefer `final` over `var` everywhere possible. Use `var` only when the type is obvious and the declaration is local.
- Use `late` sparingly and only when you are certain it will be initialised before use.
- Prefer named parameters for constructors with more than 2 parameters.
- Use `sealed` classes and pattern matching (Dart 3+) for exhaustive handling of sum types.
- Avoid dynamic typing. Every variable and parameter should have an explicit or inferred static type.
- Use `extension` methods to add functionality to existing types rather than standalone utility functions.
- Sort imports: Dart SDK â Flutter â third-party packages â local imports, separated by blank lines.

```dart
import 'dart:async';

import 'package:flutter/material.dart';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/user_profile.dart';
```

---

_Last updated: March 2026_
