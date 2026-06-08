# Onboarding

First-launch setup flow. Shown once when the user has not yet completed onboarding, and on demand from Settings.

## Files

| File | Purpose |
|---|---|
| `OnboardingView.swift` | `OnboardingWindowController` manages the `NSWindow`. `OnboardingView` is the paginated SwiftUI content: intro pages, a local-AI setup page (`LocalModelSetupView` from `Settings/`), and the permissions + launch page. |

## Page structure

The flow is linear with a Next / Back navigation bar:

1. **Intro pages** — static rows defined in `OnboardingView.pages` (brand, privacy summary, feature highlights).
2. **Local AI setup** — hardware-aware model recommendation, in-app download, and MLX runtime installation. Uses `RecommendedModelDownloadView` from `Settings/LocalModelSetupView.swift`.
3. **Ready page** — requests screen recording permission and offers a "Start Capture" button to complete onboarding.

## Adding a new onboarding page

1. Add an `OnboardingPage` entry to the `pages` array in `OnboardingView`.
2. Each page is a list of `OnboardingRow` items (icon + title + body). No additional wiring needed for navigation.

## Showing onboarding manually

Call `AppState.showOnboarding()`. The window controller is owned by `AppState` and is safe to call multiple times.
