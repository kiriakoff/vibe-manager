# Vibe Manager — Flutter frontend (web)

Тёмный glassmorphism-интерфейс дашборда: логин, сетка карточек приложений,
Start/Stop, живые логи (SSE), превью.

## Запуск в dev-режиме

```bash
flutter pub get
flutter run -d chrome --dart-define=API_BASE=http://localhost:8000
```

Бэкенд по умолчанию ожидается на том же origin (прод).
`API_BASE` переопределяет адрес API для локальной разработки.

## Сборка

```bash
flutter build web --release   # результат в build/web
```

Итоговая сборка копируется в контейнер (`/app/static`) и раздаётся
Rust-бэкендом как SPA (fallback на `index.html`).

## Структура

- `lib/main.dart` — точка входа, сессия (токен в localStorage)
- `lib/api_client.dart` — REST-клиент
- `lib/sse/sse_web.dart` — SSE-стрим логов через `fetch` (EventSource не умеет Bearer-заголовки)
- `lib/pages/` — Login, Dashboard
- `lib/widgets/` — карточка приложения, панель логов, glass-стили, тосты
