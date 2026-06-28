# AGENT.md

## Project

- Project: `flutter-local-doc-scanner`
- Stack: Flutter, camera, image_picker, permission_handler, path_provider, pdf, printing, share_plus
- Type: local document scanning mobile app

## Runtime

- Mobile runtime has no fixed HTTP port.
- For Flutter Web debugging, choose an explicit port, for example: `flutter run -d chrome --web-port 4007`.
- Analyze: `flutter analyze`.
- Test: `flutter test`.

## Data Storage

- External database: none.
- Local files: app document/cache directories via `path_provider`.
- Generated documents: local PDFs/images, share/export through Flutter plugins.

## Codex Notes

- Do not add server/database docs unless backend code is added.
- Keep platform permission changes synchronized with README.

## GitHub Commit Language

- Use English for all GitHub commit messages and pull/push related commit notes.
