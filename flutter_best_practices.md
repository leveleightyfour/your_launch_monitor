# Flutter Best Practices

A reference guide for consistent, maintainable Flutter development across all projects.

---

## Table of Contents

1. [Project Structure](#project-structure)
2. [Naming Conventions](#naming-conventions)
3. [Riverpod — Providers](#riverpod--providers)
4. [Riverpod — State & AsyncValue](#riverpod--state--asyncvalue)
5. [Riverpod — Provider Lifecycle & Invalidation](#riverpod--provider-lifecycle--invalidation)
6. [UI Architecture](#ui-architecture)
7. [Widget Design](#widget-design)
8. [Navigation](#navigation)
9. [Error Handling](#error-handling)
10. [Performance](#performance)
11. [Testing](#testing)
12. [General Dart](#general-dart)

---

## Project Structure

Organise by **feature**, not by type. Each feature folder is self-contained.

```
lib/
├── core/
│   ├── constants/
│   ├── extensions/
│   ├── theme/
│   └── utils/
├── features/
│   ├── auth/
│   │   ├── data/          # Repositories, data sources, DTOs
│   │   ├── domain/        # Models, entities, interfaces
│   │   ├── application/   # Providers, notifiers, use-case logic
│   │   └── presentation/  # Screens, widgets, controllers
│   └── settings/
│       ├── data/
│       ├── domain/
│       ├── application/
│       └── presentation/
├── shared/
│   ├── widgets/           # App-wide reusable widgets
│   └── providers/         # App-wide providers (e.g. router, theme)
└── main.dart
```

- Keep `main.dart` minimal — bootstrap only (ProviderScope, app-level config).
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

## Riverpod — Providers

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

### Code generation

Prefer the `@riverpod` annotation (via `riverpod_generator`) over manual provider definitions. Code generation reduces boilerplate, enforces correct typing, and integrates with `riverpod_lint`.

```dart
// ✅ Preferred — code-generated provider
@riverpod
Future<List<Post>> posts(PostsRef ref) async {
  return ref.watch(postRepositoryProvider).fetchAll();
}

// ✅ Code-generated notifier
@riverpod
class UserProfile extends _$UserProfile {
  @override
  Future<UserProfileModel> build() async {
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

For manual definitions (e.g. when code generation is not in use):

```dart
// ✅ Good — typed, scoped, named clearly
final userRepositoryProvider = Provider<UserRepository>((ref) {
  return UserRepository(client: ref.watch(httpClientProvider));
});

// ✅ Good — AsyncNotifierProvider
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
- Never perform side effects directly in `build()` — use `ref.listenSelf` or `ref.listen` instead.

### ref.listenSelf

Use `ref.listenSelf` inside a notifier's `build()` to react to its own state changes — for example, to log errors or trigger analytics without coupling the UI layer.

```dart
@override
Future<UserProfile> build() async {
  ref.listenSelf((previous, next) {
    next.whenOrNull(
      error: (e, st) => logger.error('UserProfile error', e, st),
    );
  });
  return ref.watch(userRepositoryProvider).fetchProfile();
}
```

### Provider dependencies

```dart
// ✅ Use ref.watch for reactive dependencies
final formattedNameProvider = Provider<String>((ref) {
  final profile = ref.watch(userProfileProvider).valueOrNull;
  return profile?.displayName ?? 'Guest';
});

// ✅ Use ref.read inside callbacks/methods (not during build)
void onButtonTap() {
  ref.read(userProfileProvider.notifier).updateDisplayName('Aden');
}

// ❌ Never use ref.watch inside callbacks or event handlers
void onButtonTap() {
  ref.watch(userProfileProvider); // BAD — causes unexpected rebuilds
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
// ✅ Use .family for parameterised providers
final postByIdProvider = FutureProvider.family<Post, String>((ref, id) {
  return ref.watch(postRepositoryProvider).fetchById(id);
});

// In widget:
final post = ref.watch(postByIdProvider('post-123'));
```

- Keep family parameters simple and serialisable (`String`, `int`, data class with `==` and `hashCode`).
- Avoid passing full model objects as family parameters.

### ProviderObserver

Use `ProviderObserver` to hook into provider state changes globally — useful for logging, analytics, and crash reporting.

```dart
class AppProviderObserver extends ProviderObserver {
  @override
  void didUpdateProvider(
    ProviderBase provider,
    Object? previous,
    Object? next,
    ProviderContainer container,
  ) {
    debugPrint('[${provider.name ?? provider.runtimeType}] $previous → $next');
  }

  @override
  void didDisposeProvider(ProviderBase provider, ProviderContainer container) {
    debugPrint('[${provider.name ?? provider.runtimeType}] disposed');
  }
}

// Register at app root
ProviderScope(
  observers: [AppProviderObserver()],
  child: const MyApp(),
)
```

### riverpod_lint

Add `riverpod_lint` to your `dev_dependencies`. It statically catches the most common Riverpod mistakes and enforces the rules in this document automatically:

- `ref.watch` used inside callbacks or event handlers
- `ref.read` used during `build()`
- Missing return type annotations on providers
- Incorrect provider type choices
- Notifiers not extending the correct base class

```yaml
# pubspec.yaml
dev_dependencies:
  riverpod_lint: ^2.0.0
  custom_lint: ^0.6.0
```

```yaml
# analysis_options.yaml
analyzer:
  plugins:
    - custom_lint
```

Treat `riverpod_lint` as a required dev dependency on all projects.

---

## Riverpod — State & AsyncValue

### Handling AsyncValue in UI

```dart
// ✅ Use .when for the full three-state pattern
ref.watch(userProfileProvider).when(
  data: (profile) => ProfileWidget(profile: profile),
  loading: () => const CircularProgressIndicator(),
  error: (e, st) => ErrorWidget(message: e.toString()),
);

// ✅ Use skipLoadingOnRefresh to prevent flicker on pull-to-refresh
ref.watch(userProfileProvider).when(
  skipLoadingOnRefresh: true,  // keep showing data while refreshing
  data: (profile) => ProfileWidget(profile: profile),
  loading: () => const CircularProgressIndicator(),
  error: (e, st) => ErrorWidget(message: e.toString()),
);

// ✅ Use .valueOrNull for optional reads where null is acceptable
final name = ref.watch(userProfileProvider).valueOrNull?.displayName;

// ✅ Use .requireValue when data is guaranteed (e.g. in tests, or after
// a .when(data:) guard). Throws if called on loading/error state.
final profile = ref.watch(userProfileProvider).requireValue;
```

### Showing stale data during refresh

Use the `previous` parameter in `.when` to keep displaying the last known data while a refresh is in progress, rather than reverting to a loading spinner.

```dart
ref.watch(userProfileProvider).when(
  skipLoadingOnRefresh: true,
  skipError: true,            // keep showing data if a refresh fails
  data: (profile) => ProfileWidget(profile: profile),
  loading: () => const CircularProgressIndicator(),
  error: (e, st) => ErrorWidget(message: e.toString()),
);
```

### Avoid overusing AsyncValue

- Don't wrap purely synchronous, non-failing state in `AsyncValue`.
- For UI-local state (expanded, selected tab), use plain state classes or `StateProvider`.

### State classes (for Notifiers with multiple fields)

```dart
// ✅ Use freezed or plain immutable classes
@freezed
class AuthState with _$AuthState {
  const factory AuthState({
    @Default(false) bool isLoading,
    User? user,
    String? errorMessage,
  }) = _AuthState;
}
```

- Always make state immutable — use `copyWith`, never mutate in place.
- Each distinct loading/error concern should be represented explicitly in the state.

---

## Riverpod — Provider Lifecycle & Invalidation

Understanding when `build()` runs and how to control caching is essential for correct Riverpod usage.

### When build() re-runs

A provider's `build()` method is called:

1. The first time it is watched.
2. When `ref.invalidate()` or `ref.refresh()` is called on it.
3. When any of its `ref.watch` dependencies change.

It does **not** re-run just because the widget tree rebuilds.

### ref.invalidate vs ref.refresh

These are the two mechanisms for manually busting a provider's cache:

```dart
// ref.invalidate — marks the provider stale. The rebuild happens lazily,
// the next time the provider is watched. Returns void.
ref.invalidate(postsProvider);

// ref.refresh — invalidates AND immediately triggers a rebuild.
// Returns the new value synchronously (or Future/Stream).
// Use when you need to await the result.
final freshPosts = await ref.refresh(postsProvider.future);
```

**Rule of thumb:** use `ref.invalidate` when you want to signal staleness without caring about the result (e.g. after a delete operation). Use `ref.refresh` when you need to await the fresh data (e.g. pull-to-refresh).

```dart
// ✅ Common pattern — pull-to-refresh
Future<void> _onRefresh() async {
  await ref.refresh(postsProvider.future);
}

// ✅ Post-mutation invalidation
Future<void> deletePost(String id) async {
  await ref.read(postRepositoryProvider).delete(id);
  ref.invalidate(postsProvider); // list will reload next time it's watched
}
```

### Keeping providers alive

By default, auto-dispose providers are destroyed when no widget is watching them. Override this for resources that are expensive to recreate or must persist across navigation.

```dart
// Option 1 — annotation (code gen)
@Riverpod(keepAlive: true)
AuthRepository authRepository(AuthRepositoryRef ref) {
  return AuthRepository();
}

// Option 2 — manual keepAlive with conditional release
@riverpod
Future<Config> appConfig(AppConfigRef ref) async {
  final link = ref.keepAlive();
  // Optionally release after a timeout to allow re-fetching
  final timer = Timer(const Duration(minutes: 5), link.close);
  ref.onDispose(timer.cancel);
  return ConfigService().load();
}
```

---

## UI Architecture

### Screen → Controller pattern

```
Screen (ConsumerWidget)
  └── watches providers, handles top-level layout
       └── Child Widgets (pure or lightly connected)
            └── delegate mutations back via notifier calls
```

- Screens are thin: they wire providers to widgets and handle navigation.
- Extract any widget over ~60 lines into its own file/class.
- Do not call `ref.read(provider.notifier).someMethod()` from deep inside the widget tree. Pass callbacks down instead.

### ConsumerWidget vs ConsumerStatefulWidget

```dart
// ✅ Prefer ConsumerWidget when no local widget state is needed
class ProfileScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) { ... }
}

// ✅ Use ConsumerStatefulWidget when you need initState/dispose
// e.g. AnimationController, TextEditingController, focus nodes
class SearchScreen extends ConsumerStatefulWidget {
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}
```

- Do not convert to `ConsumerStatefulWidget` just to store state that belongs in a provider.

### setState with Riverpod

`setState` is an **anti-pattern** for anything beyond trivial, purely local UI rendering state.

```dart
// ✅ setState is acceptable for ephemeral, single-widget render concerns
// with no business logic and no interest from any other widget
class _CardState extends ConsumerState<Card> {
  bool _isHovered = false; // fine — hover affects only this widget's render

  @override
  Widget build(BuildContext context) { ... }
}

// ❌ Never use setState for:
// — loading or async flags
// — form field values with validation
// — state that any other widget might need
// — anything with business logic attached
setState(() => _isLoading = true); // put this in a Notifier
setState(() => _hasError = true);  // put this in AsyncValue state
```

**Rule:** if a second widget could ever need to read this state, or it involves business logic, it belongs in a provider. `setState` is for pure rendering concerns that are truly local and ephemeral to a single widget.

Acceptable uses of `setState` alongside Riverpod:

| OK to use setState for            | Instead use a provider for         |
| --------------------------------- | ---------------------------------- |
| Hover / focus visual state        | Loading flags                      |
| Animation controller ticks        | Form values with validation        |
| Scroll position (local only)      | Error state                        |
| TextEditingController lifecycle   | Selected items / filters           |

### Do not pass WidgetRef down the tree

`WidgetRef` is a build-time construct tied to a specific widget's lifecycle. It is not a service and must not be passed as a constructor parameter.

```dart
// ❌ Anti-pattern — ref passed into a child or service
class MyService {
  final WidgetRef ref; // DO NOT do this
  MyService(this.ref);
}

MyChildWidget(ref: ref) // DO NOT do this

// ✅ Instead, pass callbacks or make the child a ConsumerWidget
MyChildWidget(
  onSave: () => ref.read(myProvider.notifier).save(),
)

// ✅ Or let the child watch its own providers directly
class MyChildWidget extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(myProvider);
    ...
  }
}
```

### Do not use ref in initState

`ref` is not available before the widget is fully built. Accessing it in `initState` directly will throw. Use `ref.listenSelf` on the provider side, or schedule the call with `addPostFrameCallback`.

```dart
// ❌ Will throw — ref not ready in initState
@override
void initState() {
  super.initState();
  ref.read(myProvider.notifier).init(); // BAD
}

// ✅ Schedule after the first frame
@override
void initState() {
  super.initState();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    ref.read(myProvider.notifier).init();
  });
}

// ✅ Or use ref.listenSelf in the notifier's build() instead
```

### Listening to providers for side effects

```dart
// ✅ Use ref.listen for navigation, snackbars, dialogs — NOT ref.watch
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
// ✅ Extracted class — rebuilds independently
class AvatarWidget extends StatelessWidget { ... }

// ❌ Helper method — always rebuilds with parent
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
- Use `Padding` as a wrapper rather than adding padding to `Container` where possible.

### Theme over hardcoded values

```dart
// ✅ Use theme tokens
Text(
  'Hello',
  style: Theme.of(context).textTheme.titleMedium,
)

// ❌ Avoid hardcoded colours / sizes in widget code
Text('Hello', style: TextStyle(fontSize: 18, color: Color(0xFF333333)))
```

- Define all colours, typography, spacing, and border radii in `ThemeData`.
- Use `ColorScheme` tokens (`primary`, `surface`, `onPrimary`, etc.) not raw hex values.

---

## Navigation

- Use a single, declarative router — **go_router** is the standard choice.
- Define all routes in a single file (`router.dart` or `app_router.dart`).
- Pass IDs/primitive values via path/query parameters, not full model objects.
- Keep navigation logic out of Notifiers — handle it in the UI layer via `ref.listen`.

```dart
// ✅ Navigate via GoRouter
context.go('/profile/$userId');
context.push('/settings');

// ❌ Avoid Navigator.of(context).push with MaterialPageRoute inline
```

---

## Error Handling

- Define a sealed `Failure` / `AppError` type for domain-level errors.
- Use `AsyncValue.guard()` in notifiers to safely capture exceptions into state.
- Never swallow errors silently — always log and surface them.
- Show user-facing errors in the UI, not raw exception messages.

```dart
// ✅ Sealed error type
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
// ✅ Only rebuilds when displayName changes, not the whole profile
final name = ref.watch(
  userProfileProvider.select((p) => p.valueOrNull?.displayName),
);
```

- Avoid creating objects (lists, maps, styles) inside `build()` — move them to constants or memoize.
- Use `ListView.builder` / `ListView.separated` for all lists of unknown length. Never `ListView` with `children:` for dynamic content.
- Profile with Flutter DevTools before optimising. Don't prematurely extract widgets based on intuition alone.
- Avoid large `Stack` hierarchies and excessive `Opacity` widgets (both are GPU-expensive).

---

## Testing

### Unit tests — Notifiers

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

### overrideWith vs overrideWithValue

| Method                | Use for                                                        |
| --------------------- | -------------------------------------------------------------- |
| `overrideWithValue`   | Replacing the value directly (services, simple dependencies)   |
| `overrideWith`        | Replacing the entire provider factory (notifiers, complex DI)  |

```dart
// overrideWithValue — replaces the resolved value
userRepositoryProvider.overrideWithValue(FakeUserRepository())

// overrideWith — replaces the provider factory; useful for notifiers
userProfileProvider.overrideWith(() => FakeUserProfileNotifier())
```

### Testing AsyncNotifier state transitions

Test the full `AsyncLoading` → `AsyncData` / `AsyncError` lifecycle, not just the final state:

```dart
test('shows loading then data', () async {
  final container = ProviderContainer(overrides: [
    userRepositoryProvider.overrideWithValue(SlowFakeUserRepository()),
  ]);
  addTearDown(container.dispose);

  // Trigger build
  container.read(userProfileProvider);

  // Should be loading immediately
  expect(container.read(userProfileProvider), isA<AsyncLoading>());

  // Await completion
  await container.read(userProfileProvider.future);

  expect(
    container.read(userProfileProvider).valueOrNull?.displayName,
    'Test User',
  );
});
```

### Testing ref.listen side effects

To verify side effects triggered by `ref.listen` (navigation, snackbars), use `ProviderContainer.listen` in unit tests or a fake observer in widget tests:

```dart
test('emits error state on failed submit', () async {
  final container = ProviderContainer(overrides: [
    submitFormProvider.overrideWith(() => FailingSubmitNotifier()),
  ]);
  addTearDown(container.dispose);

  final states = <AsyncValue<void>>[];
  container.listen(submitFormProvider, (_, next) => states.add(next));

  await container.read(submitFormProvider.notifier).submit();

  expect(states.last, isA<AsyncError>());
});
```

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
- Sort imports: Dart SDK → Flutter → third-party packages → local imports, separated by blank lines.

```dart
import 'dart:async';

import 'package:flutter/material.dart';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/user_profile.dart';
```

---

_Last updated: April 2026_