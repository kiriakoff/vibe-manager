# Спецификация проекта: "Vibe Manager" (v0.5)

## 1. Концепция
Одностраничное веб-приложение (SPA), работающее на хосте с Docker. Служит пультом управления для приложений пользователей, абстрагируя контейнеризацию через понятия **Start/Stop**.

**Философия:** Minimal UI, Dark Mode by default, Glassmorphism элементы, мгновенный отклик, многопользовательская изоляция.

---

## 2. Технологический стек

| Компонент | Технология | Примечание |
|-----------|------------|------------|
| **Backend** | Rust (axum + tokio) | Асинхронность для SSE-стриминга, Docker CLI для управления контейнерами |
| **Frontend** | Flutter (web) | Тёмная тема, glassmorphism (BackdropFilter), адаптивная сетка |
| **Хранение состояния** | Без БД | Состояние из Docker API (labels, status), конфиг через env, данные в `/data/vibemanager/` |
| **Авторизация** | JWT + текстовый файл | Логин и bcrypt-хеш в `/data/vibemanager/auth/users.txt`, JWT_SECRET генерируется автоматически |
| **Инфраструктура** | Docker Socket | `/var/run/docker.sock` монтируется в контейнер сервиса |
| **Управление контейнерами** | docker-ce-cli + docker-compose-plugin | `docker compose up -d` / `down` для приложений |
| **Интеграция** | File Browser | Отдельный сервис, данные в `/data/filebrowser/files/` (плоская структура) |
| **Preview** | Headless Chromium | Внутри контейнера Vibe Manager, скриншоты `http://<fqdn>` (1280x720) |
| **SSL/TLS** | Traefik + Let's Encrypt | Автоматическая выдача сертификатов через HTTP-01 challenge |

---

## 3. Структура директорий

```
# В репозитории
vibemanager/
├── backend/                 # Rust-бэкенд (axum)
│   ├── Cargo.toml
│   ├── Cargo.lock
│   └── src/
│       ├── main.rs          # точка входа, роутер, раздача SPA
│       ├── lib.rs           # модули и сборка Router
│       ├── config.rs        # env-конфиг, jwt_secret (load/generate)
│       ├── auth.rs          # JWT, users.txt, bcrypt, extractor CurrentUser
│       ├── apps.rs          # сканирование приложений, FQDN-валидация
│       ├── docker.rs        # compose-файлы, start/stop, логи (follow)
│       ├── preview.rs       # скриншоты chromium + PNG-placeholder
│       ├── handlers.rs      # HTTP-обработчики, SSE
│       └── bin/create-user.rs  # CLI создания пользователей
├── frontend/                # Flutter-приложение (web)
│   ├── pubspec.yaml
│   ├── web/                 # index.html, manifest.json
│   └── lib/
│       ├── main.dart        # сессия (токен в localStorage)
│       ├── api_client.dart  # REST-клиент
│       ├── sse/sse_web.dart # SSE через fetch (dart:js_interop)
│       ├── pages/           # LoginPage, DashboardPage
│       └── widgets/         # AppCard, LogsSheet, GlassCard, toasts
├── Dockerfile               # 3 стадии: flutter build → cargo build → runtime
├── docker-compose.yml
├── setup.sh
└── .env.example

# На хосте
/data/vibemanager/          # Персистентные данные (монтируется в контейнер)
├── auth/
│   ├── users.txt           # Логин:bcrypt-хеш пароля
│   └── jwt_secret          # Автогенерируемый JWT секрет (при первом запуске)
├── previews/
│   └── <fqdn>.png          # Скриншоты приложений
└── compose/
    └── <owner>/<fqdn>/
        └── docker-compose.yml  # Временные compose-файлы для контейнеров

/data/filebrowser/files/    # Данные File Browser (плоская структура)
└── <fqdn>/
    └── index.html          # Приложение (обязательно)

# В контейнере
/app/vibe-manager           # Бинарник бэкенда
/app/create-user            # CLI создания пользователей
/app/static/                # Собранный Flutter web (SPA)
/data/                      # Персистентные данные (смонтировано из /data/vibemanager)
/filebrowser/               # Смонтированный /data/filebrowser/files
```

### Монтирование томов
| Хост | Контейнер | Режим | Назначение |
|------|-----------|-------|------------|
| `/data/vibemanager` | `/data` | rw | Персистентные данные Vibe Manager |
| `/data/filebrowser/files` | `/filebrowser` | ro | Папки приложений File Browser |
| `/var/run/docker.sock` | `/var/run/docker.sock` | rw | Docker API |

---

## 4. Конфигурация (переменные окружения)

| Переменная | По умолчанию | Описание |
|------------|--------------|----------|
| `JWT_SECRET` | автогенерация → `/data/auth/jwt_secret` | Секрет HS256; при отсутствии генерируется и сохраняется |
| `JWT_EXPIRATION_HOURS` | `24` | Время жизни JWT |
| `PORT` | `8000` | Порт HTTP-сервера |
| `DATA_ROOT` | `/data` | Корень персистентных данных |
| `FILEBROWSER_ROOT` | `/filebrowser` | Корень приложений внутри контейнера |
| `FILEBROWSER_HOST` | `/data/filebrowser/files` | Путь на хосте для volume-маунтов в compose-файлах |
| `STATIC_DIR` | `/app/static` | Каталог собранного Flutter-фронтенда |
| `RUST_LOG` | `info,vibe_manager=debug` | Фильтр логирования (tracing) |

---

## 5. Функциональные требования

### 5.1. Система авторизации и роли
- **Хранение учётных данных:**
  - Файл: `/data/vibemanager/auth/users.txt`
  - Формат: `username:bcrypt_hash`
  - Создание/обновление: `/app/create-user <username> <password>` (CLI, входит в образ)
  - JWT_SECRET: генерируется автоматически при первом запуске, сохраняется в `/data/vibemanager/auth/jwt_secret`
- **Ролевая модель:**
  - Каждое приложение принадлежит владельцу (лейбл `vibe.owner` / имя директории)
  - Пользователь видит **только свои приложения**
  - Админ (пользователь `admin`) видит все приложения
- **Сессии:** JWT HS256, payload `{sub, exp}`, экспирация 24 часа; токен хранится в localStorage, передаётся в `Authorization: Bearer`

### 5.2. Дашборд (главная страница)
- **Фильтрация приложений:**
  - Отображаются приложения из папок File Browser (валидный FQDN + `index.html`)
  - Системные контейнеры **не отображаются**
- **Карточка приложения:**
  | Элемент | Описание |
  |---------|----------|
  | Превью | Изображение из `/data/vibemanager/previews/<fqdn>.png` (fallback — иконка 🌐) |
  | Название | Имя папки (FQDN), например `blog.mysite.com` |
  | Статус | **Напрямую из Docker API** (`running`, `exited`, etc.), светящийся индикатор |
  | Кнопки | ⏯ **Start/Stop** (одна кнопка, меняет цвет/текст), 📜 **Logs**, 🖼 **Refresh preview**, 🔗 **Open site** (только для running) |
- **Действия:**
  - **Start** — создаёт и запускает контейнер через `docker compose up -d`, затем обновляет превью
  - **Stop** — останавливает и удаляет контейнер через `docker compose down`
  - **Logs** — нижняя панель с живым SSE-стримом, авто-скролл, копирование, переподключение
- **Обновление данных:** тихий поллинг `/api/apps` каждые 15 с + pull-to-refresh

### 5.3. Интеграция с File Browser
- **Источник данных:**
  - Корневая папка: `/data/filebrowser/files/` (плоская структура)
  - Каждое приложение = папка с именем FQDN (например, `blog.mysite.com/`)
  - Обязательное условие: внутри папки должен быть `index.html`
- **Валидация FQDN:** минимум 3 метки (`sub.domain.tld`); метки — `[A-Za-z0-9-]`, без `-` по краям, длина ≤ 63; TLD — только буквы, ≥ 2 символов
- **Обнаружение приложений:**
  - Backend сканирует корневую папку при каждом запросе `/api/apps`
  - Статус берётся из `docker inspect --format {{.State.Status}}`
- **Генерация превью:**
  | Сценарий | Действие |
  |----------|----------|
  | При загрузке панели | Генерировать превью, если контейнер running, а превью отсутствует (в фоне) |
  | После успешного Start | Обновить превью автоматически |
  | Кнопка Refresh preview | Принудительное обновление |
  | Рендер | Полный сайт через `http://<fqdn>` (Traefik), внешний вид 1:1 |
  | Хранение | `/data/vibemanager/previews/<fqdn>.png` |
  | Ошибка | PNG-placeholder 800x600 (цвет slate) |

### 5.4. Управление контейнерами (Start/Stop)
- **Имя контейнера:** равно имени папки (FQDN), например `blog.mysite.com`
- **Start (Создание):**
  1. Генерация временного `docker-compose.yml` в `/data/vibemanager/compose/<owner>/<fqdn>/`
  2. Запуск `docker compose -f <path> up -d` (таймаут 60 с)
  3. Конфигурация контейнера:
     ```yaml
     services:
       app:
         Image: nginx:alpine
         container_name: <fqdn>
         Volumes:
           - /data/filebrowser/files/<fqdn>:/usr/share/nginx/html:ro
         Network: proxy (external)
         Labels:
           vibe.manager: "true"
           vibe.owner: "<owner>"
           vibe.fqdn: "<fqdn>"
           traefik.enable: "true"
           traefik.http.routers.<fqdn с _>.rule: "Host(`<fqdn>`)"
           traefik.http.routers.<fqdn с _>.entrypoints: "websecure"
           traefik.http.routers.<fqdn с _>.tls: "true"
           traefik.http.routers.<fqdn с _>.tls.certresolver: "letsEncrypt"
           traefik.http.services.<fqdn с _>.loadbalancer.server.port: "80"
     ```
- **Stop (Удаление):**
  1. Если compose-файл существует: `docker compose -f <path> down`
  2. Иначе (файл утерян): `docker rm -f <fqdn>`; «No such container» трактуется как успех
  3. Контейнер полностью удаляется (образ остаётся)

### 5.5. Логи (живой стрим)
- `GET /api/apps/{fqdn}/logs` — SSE
- Backend запускает `docker logs --tail 100 --follow <fqdn> 2>&1`
- Каждая строка — событие `data: <line>`; завершение — `data: [DONE]`
- Keep-alive комментарий каждые 15 с
- При отключении клиента дочерний процесс `docker logs` автоматически убивается (`kill_on_drop`)

---

## 6. Архитектура и безопасность

### 6.1. Доступ к Docker Socket
- Сервис запускается с монтированием `/var/run/docker.sock`
- **Митигация:**
  - Обязательная авторизация в приложении (все `/api/*` эндпоинты, кроме превью)
  - Изоляция пользователей по путям в File Browser
  - Валидация FQDN во всех path-параметрах (защита от инъекций в shell-команды)
  - Запрет на прямой доступ к Docker API кроме через Vibe Manager

### 6.2. Сетевая модель
| Параметр | Значение |
|----------|----------|
| Сеть Traefik | `proxy` (external) |
| Entrypoint | `websecure` |
| HTTPS | Обязательно (TLS через Traefik, авто-сертификаты Let's Encrypt) |
| SSL Challenge | HTTP-01 (через entrypoint `web`) |
| Порт сервиса | 8000 (внутри), 8080 (наружу в compose) |

### 6.3. Статусы контейнеров (из Docker API)
| Статус | Отображение | Цвет | Кнопка |
|--------|-------------|------|--------|
| `running` | Running | 🟢 Зелёный | Stop |
| `exited` | Stopped | 🔴 Красный | Start |
| `restarting` | Restarting | 🟡 Жёлтый | Stop |
| `paused` | Paused | 🟠 Оранжевый | Start |
| `dead` | Dead | ⚫ Тёмно-серый | Start |
| `created` | Created | 🔵 Синий | Start |
| `not found` | Not Deployed | ⚪ Серый | Start |

---

## 7. UI/UX Детали ("Вайб")

| Элемент | Реализация (Flutter) |
|---------|----------------------|
| **Фон** | Глубокий тёмный градиент (slate-900 `#0f172a` → slate-800) |
| **Карточки** | `GlassCard`: BackdropFilter (blur 14) + полупрозрачная заливка + тонкая рамка |
| **Акценты** | Неоновые цвета статусов со свечением (BoxShadow), cyan/blue градиенты |
| **Анимации** | Плавный переход login↔dashboard (AnimatedSwitcher), спиннеры на кнопках |
| **Уведомления** | Тосты (SnackBar floating): зелёная рамка — успех, красная — ошибка |
| **Логин-форма** | Центрированная glass-карточка, валидация, показ/скрытие пароля |
| **Кнопка Start/Stop** | Зелёная «Start» / красная «Stop», спиннер во время операции |
| **Панель логов** | Нижняя панель (82% высоты), моно-шрифт, авто-скролл, копирование, «--- Connection closed ---» |
| **Сетка** | Адаптивно: 1 колонка (<620px) / 2 (<1040) / 3 (<1460) / 4 |

---

## 8. API Endpoints

| Метод | Эндпоинт | Описание | Доступ |
|-------|----------|----------|--------|
| POST | `/auth/login` | Логин, возврат JWT `{access_token, token_type}` | Публичный |
| GET | `/api/apps` | Список приложений `{apps: [{fqdn, status, owner, has_preview}]}` | Авторизованный |
| POST | `/api/apps/<fqdn>/start` | Start (docker compose up) | Авторизованный |
| POST | `/api/apps/<fqdn>/stop` | Stop (docker compose down) | Авторизованный |
| GET | `/api/apps/<fqdn>/logs` | Живой стрим логов (SSE) | Авторизованный |
| GET | `/api/apps/<fqdn>/status` | Статус контейнера `{fqdn, status}` | Авторизованный |
| GET | `/api/previews/<fqdn>` | PNG-превью | Публичный (для `<img>`) |
| POST | `/api/previews/<fqdn>/refresh` | Принудительное обновление превью | Авторизованный |
| GET | `/api/status` | Health check `{status, version}` | Публичный |
| GET | `/<любой путь>` | SPA fallback: статика Flutter, иначе `index.html` | Публичный |

Ошибки возвращаются в формате FastAPI-совместимого JSON: `{"detail": "..."}`.

---

## 9. Docker Compose (Vibe Manager)

```yaml
services:
  vibemanager:
    build: .
    container_name: vibemanager
    restart: unless-stopped
    ports:
      - "8080:8000"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /data/vibemanager:/data
      - /data/filebrowser/files:/filebrowser:ro
    networks:
      - proxy
    environment:
      - FILEBROWSER_ROOT=/filebrowser
      - FILEBROWSER_HOST=/data/filebrowser/files
      - DATA_ROOT=/data
      - STATIC_DIR=/app/static
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.vibemanager.rule=Host(`vibe.yourdomain.com`)"
      - "traefik.http.routers.vibemanager.entrypoints=websecure"
      - "traefik.http.routers.vibemanager.tls=true"
      - "traefik.http.routers.vibemanager.tls.certresolver=letsEncrypt"

networks:
  proxy:
    external: true
```

---

## 10. Dockerfile (3 стадии)

```dockerfile
# Stage 1: Flutter web build
FROM ghcr.io/cirruslabs/flutter:3.32.5 AS frontend-builder
# flutter pub get && flutter build web --release → build/web

# Stage 2: Rust build (с кэшированием зависимостей через stub-исходники)
FROM rust:1-slim AS backend-builder
# cargo build --release → vibe-manager, create-user

# Stage 3: Runtime
FROM debian:bookworm-slim
# apt: chromium (скриншоты), docker-ce-cli + docker-compose-plugin (управление),
#      fonts-liberation, ca-certificates, curl, gnupg
# COPY: бинарники + /app/static (из Stage 1)
# ENV: PORT=8000, DATA_ROOT=/data, FILEBROWSER_ROOT=/filebrowser, ...
# CMD ["/app/vibe-manager"]
```

**Примечания:**
- JWT_SECRET генерируется автоматически в `config.rs` при первом запуске
- Логирование через `tracing`, уровень настраивается `RUST_LOG`
- Docker CLI установлен для управления контейнерами приложений через `docker compose`

---

## 11. Локальная разработка

```bash
# Backend (порт 8000)
cd backend
DATA_ROOT=/tmp/vm-data cargo run
cargo run --bin create-user admin admin123   # создание пользователя
cargo test && cargo clippy                   # тесты и линтер

# Frontend (dev-сервер, прокидываем адрес API)
cd frontend
flutter run -d chrome --dart-define=API_BASE=http://localhost:8000
flutter analyze && flutter test              # тесты и линтер
flutter build web --release                  # сборка в build/web
```

CI (`.github/workflows/deploy.yml`): на push в `master` образ собирается в GHCR, затем триггерится деплой роли `vibe-manager`.

---

## 12. История версий

### v0.5 — переписывание стека
| Аспект | Было (v0.4) | Стало (v0.5) |
|--------|-------------|--------------|
| **Backend** | Python (FastAPI) | Rust (axum + tokio) |
| **Frontend** | React (Vite) + Tailwind | Flutter (web) |
| **Логи** | Снимок последних 100 строк | Живой стрим (`docker logs --follow`) через SSE |
| **Превью fallback** | PIL placeholder | PNG placeholder (крейт `png`) |
| **Создание пользователей** | `create_user.py` | `create-user` (Rust CLI) |
| **Статика SPA** | Встроенный StaticFiles | `ServeDir` + fallback на `index.html` |

Контракты API, форматы файлов (`users.txt`, `jwt_secret`, compose-файлы),
лейблы контейнеров и структура томов сохранены без изменений.

### v0.4 — compose-модель
- Start = `docker compose up -d` (создание + запуск), Stop = `docker compose down`
- Контейнер временный: создаётся/удаляется по запросу
- Превью: всегда при загрузке панели (если отсутствует) + после Start
- Traefik + Let's Encrypt автоматически, плоская структура File Browser
