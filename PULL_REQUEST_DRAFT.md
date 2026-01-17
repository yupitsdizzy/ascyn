Title: Fix BuildContext async-gap in TasksPage; test encoding fix

Summary

- Fixes analyzer `use_build_context_synchronously` warnings in `lib/features/tasks/ui/tasks_page.dart` by capturing `ScaffoldMessenger`/`Navigator` before awaiting async calls and adding a `mounted` check before showing dialogs.
- Fixes a non-UTF8 apostrophe in `test/widget_test.dart` that caused `flutter test` to crash.

Files changed

- lib/features/tasks/ui/tasks_page.dart
- test/widget_test.dart

Why

- Prevents runtime UI issues when showing dialogs or SnackBars after async operations and keeps the analyzer clean.
- Allows test runner to read placeholder tests (avoids encoding crash) so CI can run tests.

Testing

- Ran `flutter analyze` — no issues found.
- Ran full test suite (`flutter test --reporter=expanded`) — all tests passed locally.

Notes / Follow-ups

- Branch: `fix/tasks-async-gap` (local). I can push this branch to a remote you provide.
- Suggested PR body includes the context above and the patch attached if needed.

Next steps (suggested)

- Push branch and open PR.
- Set up CI to run analyzer + tests (with Firestore emulator for integration tests).
- Add concurrency & pagination integration tests for ledger edge-cases.

---

Patch available: `fix-tasks-async-gap.patch` (one-commit patch in repository parent directory).