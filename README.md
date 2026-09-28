# Vibe Manager (v0.5)

Одностраничное веб-приложение — пульт управления приложениями на хосте с Docker.
Абстрагирует контейнеризацию через понятия **Start/Stop**.

**Философия:** Minimal UI, Dark Mode by default, Glassmorphism, мгновенный отклик, многопользовательская изоляция.

## Стек (v0.5 — полное переписывание)

| Компонент | Технология |
|-----------|------------|
| **Backend** | Rust (axum, tokio) — `backend/` |
| **Frontend** | Flutter (web) — `frontend/` |
| **Хранение состояния** | Без БД: Docker API + файлы в `/data` |
| **Авторизация** | JWT (HS256, 24 ч) + `users.txt` (bcrypt) |
| **Управление контейнерами** | Docker CLI + compose plugin (`docker compose up/down`) |
| **Превью** | Headless Chromium (`--screenshot`, 1280x720) |
| **SSL/TLS** | Traefik + Let's Encrypt (HTTP-01) |

## Структура

```
backend/               Rust-бэкенд (axum)
  ├── src/main.rs      точка входа, роутер, раздача SPA
  ├── src/auth.rs      JWT, users.txt, bcrypt
  ├── src/apps.rs      сканирование приложений, FQDN-валидация
  ├── src/docker.rs    генерация compose-файлов, start/stop, логи
  ├── src/preview.rs   скриншоты (chromium) + placeholder
  └── src/bin/create-user.rs  CLI создания пользователей
frontend/              Flutter-приложение (web)
  └── lib/             login, dashboard, карточки, SSE-логи
Dockerfile             3 стадии: flutter build → cargo build → runtime
docker-compose.yml     деплой (сеть proxy + Traefik)
```

Данные на хосте:

```
/data/vibemanager/
  ├── auth/users.txt       # username:bcrypt_hash
  ├── auth/jwt_secret      # автогенерация при первом запуске
  ├── previews/<fqdn>.png  # скриншоты приложений
  └── compose/<owner>/<fqdn>/docker-compose.yml
/data/filebrowser/files/<fqdn>/index.html   # приложения (плоско)
```

## API

| Метод | Эндпоинт | Описание |
|-------|----------|----------|
| POST | `/auth/login` | Логин, возврат JWT |
| GET | `/api/apps` | Список приложений (admin видит все) |
| POST | `/api/apps/{fqdn}/start` | `docker compose up -d` |
| POST | `/api/apps/{fqdn}/stop` | `docker compose down` |
| GET | `/api/apps/{fqdn}/logs` | SSE, живые логи (`docker logs --follow`) |
| GET | `/api/apps/{fqdn}/status` | Статус контейнера из Docker API |
| GET | `/api/previews/{fqdn}` | PNG-превью (публичный, для `<img>`) |
| POST | `/api/previews/{fqdn}/refresh` | Пересоздать превью |
| GET | `/api/status` | Health check |

## Локальная разработка

Backend:

```bash
cd backend
DATA_ROOT=/tmp/vm-data cargo run
# пользователь: cargo run --bin create-user admin admin123
```

Frontend (в другом терминале):

```bash
cd frontend
flutter run -d chrome --dart-define=API_BASE=http://localhost:8000
```

Тесты и проверки:

```bash
cd backend && cargo test && cargo clippy
cd frontend && flutter analyze && flutter test
```

## Деплой

1. `./setup.sh` — создаёт директории, собирает образ, создаёт admin/admin123 и запускает.
2. Поправьте `docker-compose.yml` (Host rule под ваш домен) и `docker compose up -d`.

CI (`.github/workflows/deploy.yml`) собирает образ в GHCR на push в `master`.

## Модель доступа

- Каждый пользователь видит свои приложения; пользователь `admin` — все.
- Изоляция через имена папок File Browser (FQDN = `sub.domain.tld` с `index.html`).
- Контейнеры помечаются лейблами `vibe.manager`, `vibe.owner`, `vibe.fqdn`.
