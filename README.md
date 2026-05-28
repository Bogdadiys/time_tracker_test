# time_tracker_test

> Тестовий проєкт для співбесіди: сервіс обліку робочого часу та
> відвідуваності співробітників на базі Erlang/OTP, Cowboy, RabbitMQ та
> Postgres.

## Зміст

1. [Вступ](#вступ)
2. [Загальний опис](#загальний-опис)
   - [Предметна область](#предметна-область)
   - [Сценарії використання](#сценарії-використання)
3. [Архітектура](#архітектура)
   - [Високорівнева схема](#високорівнева-схема)
   - [Технологічний стек](#технологічний-стек)
   - [Шлях обробки запиту](#шлях-обробки-запиту)
   - [Компоненти системи](#компоненти-системи)
4. [Модель даних](#модель-даних)
5. [Протокол та формат відповіді](#протокол-та-формат-відповіді)
6. [HTTP API](#http-api)
7. [RabbitMQ (RPC)](#rabbitmq-rpc)
8. [Валідація](#валідація)
9. [Конфігурація](#конфігурація)
10. [Збірка та запуск](#збірка-та-запуск)
11. [Тестування](#тестування)
12. [Відомі обмеження](#відомі-обмеження)

---

## Вступ

`time_tracker_test` — навчально-демонстраційний проєкт, створений у рамках
тестового завдання для співбесіди. Його мета — показати типовий бекенд-сервіс
на стеку Erlang/OTP, який охоплює найпоширеніші задачі реальних систем:

- приймання запитів через **два транспорти** з єдиною бізнес-логікою —
  HTTP API (Cowboy) та RPC поверх RabbitMQ (`amqp_client`);
- валідацію вхідних даних (`liver`);
- збереження у реляційній БД (Postgres через `epgsql`);
- агрегацію та видачу статистики.

Проєкт навмисно тримається мінімальним за обсягом коду, але повним за
переліком технологій. Він не є частиною продакшн-екосистеми Pibox і не
призначений для розгортання у реальному оточенні.

## Загальний опис

### Предметна область

Сервіс моделює облік відвідуваності працівників за допомогою
**карток (RFID/NFC)**:

- кожному **користувачу** задається очікуваний робочий графік (час приходу,
  час відходу, кількість робочих днів на тиждень);
- до користувача прив'язуються одна чи кілька **карток** (UUID);
- «дотик» карткою (`touch`) фіксує **прихід** або **відхід** у журналі
  `time_log`, автоматично обчислюючи запізнення (`is_late`) та ранній відхід
  (`is_leave`);
- **винятки** (`user_exclusions`) — заздалегідь узгоджені відхилення від
  графіку: `come later` (дозволено прийти пізніше), `leave earlier`
  (дозволено піти раніше), `full-time` (відпустка/вихідний). Винятки роблять
  відповідне запізнення/відхід «з поважної причини»;
- **статистика** агрегує відпрацьований час, кількість запізнень/ранніх
  відходів (з причиною та без) і кількість вихідних/відпусток за період.

### Сценарії використання

1. **Реєстрація графіку.** `POST /user/create`, далі `POST /work_time/set`
   задає очікувані години та робочі дні.
2. **Прив'язка картки.** `POST /card/assign` пов'язує UUID картки з
   користувачем.
3. **Облік приходу/відходу.** `POST /card/touch` — перший дотик за добу
   фіксує прихід, наступний оновлює час відходу. Відповідь містить
   `event_type` = `arrival` | `leave`.
4. **Винятки.** `POST /work_time/add_exclusion` реєструє узгоджене
   відхилення на період.
5. **Звіти.** `POST /work_time/history_by_user` повертає журнал, а
   `POST /work_time/statistic_by_user` — агреговану статистику за
   `week` / `month` / `year` / `all_time`.

---

## Архітектура

### Високорівнева схема

```
   HTTP client ──▶ time_tracker_http_handler ─┐
                                              ├─▶ protocol:decode
   AMQP client ──▶ time_tracker_mq_handler ───┘        │
                   (gen_server, RPC)                   ▼
                                              validator:validate (liver)
                                                       │
                                                       ▼
                                          handler_utils:dispatch
                                                       │
                          ┌────────────────────────────┼────────────────────────┐
                          ▼                            ▼                         ▼
                   user_api                       card_api               work_time_api
                          └────────────────────────────┼────────────────────────┘
                                                       ▼
                                            time_tracker_db (epgsql)
                                                       │
                                                       ▼
                                                   Postgres
```

Обидва транспорти зводяться до однієї точки — `handler_utils:dispatch/2`, тож
бізнес-логіка не залежить від способу доставки повідомлення.

### Технологічний стек

- **Erlang/OTP** + **erlang.mk** + **relx** (релізи).
- **Cowboy 2.10.0** — HTTP-сервер.
- **amqp_client 3.12.13** — клієнт RabbitMQ.
- **epgsql 4.8.0** — драйвер Postgres.
- **jsx 3.1.0** — кодування/декодування JSON.
- **liver (master)** — валідація запитів.

### Шлях обробки запиту

1. Транспорт отримує повідомлення (тіло HTTP-запиту або payload AMQP) і
   визначає `Path` (URL-шлях для HTTP; заголовок `method` для AMQP).
2. `time_tracker_protocol:decode/2` декодує тіло за `content-type`
   (підтримується `application/json`).
3. `time_tracker_validator:validate/2` перевіряє дані за схемою `liver` для
   цього шляху.
4. `time_tracker_handler_utils:dispatch/2` маршрутизує до відповідної функції
   `*_api`.
5. `*_api` виконує запит через `time_tracker_db` і повертає `{ok, _}` / `ok`
   / `{error, _}`.
6. `time_tracker_handler_utils:encode_result/1` загортає результат у JSON.
7. HTTP відповідає кодом статусу; MQ публікує відповідь у чергу `reply_to`
   з тим самим `correlation_id` (RPC-патерн).

### Компоненти системи

| Модуль | Шар | Призначення |
|---|---|---|
| `time_tracker_test_app` | OTP | Точка входу: реєструє правила валідації, піднімає Cowboy listener, запускає супервізор. |
| `time_tracker_test_sup` | OTP | Кореневий супервізор (`one_for_one`), наглядає за `time_tracker_mq_handler`. |
| `time_tracker_http_handler` | handlers | Cowboy-handler, catch-all `"/[...]"`, приймає лише `POST`. |
| `time_tracker_mq_handler` | handlers | `gen_server`-споживач RabbitMQ; обробляє повідомлення в RPC-стилі, стежить за з'єднанням/каналом через `monitor`. |
| `time_tracker_protocol` | wrappers | JSON decode/encode (`jsx`). |
| `time_tracker_validator` | wrappers | Схеми `liver` + кастомні правила `uuid`, `time`, `iso_dt`. |
| `time_tracker_amqp` | wrappers | Тонка обгортка над `amqp_client` (connect, channel, declare, consume, publish, ack). |
| `time_tracker_db` | wrappers | Обгортка над `epgsql` (connect/equery/close, `to_map/2`). |
| `time_tracker_user_api` | api | Користувачі: create / delete / list. |
| `time_tracker_card_api` | api | Картки: touch / assign / delete / list_by_user / delete_all_by_user. |
| `time_tracker_work_time_api` | api | Графік, винятки, історія, статистика. |
| `time_tracker_handler_utils` | utils | Маршрутизація `dispatch/2` та формування відповіді `encode_result/1`. |
| `time_tracker_utils` | utils | Форматування часу (`time_to_binary/1`). |

> Вихідні файли handler-ів лежать у каталозі `src/handelrs/` (саме так,
> з історичним одруком у назві).

---

## Модель даних

Повна DDL-схема Postgres лежить у [`db.sql`](db.sql) і застосовується одним
файлом. Таблиці:

- **users** — `id` (serial PK), `name`, `expected_start_time` (time, дефолт
  `09:00:00`), `expected_stop_time` (time, дефолт `18:00:00`), `expected_days`
  (smallint, дефолт `5`), `reg_date` (date, дефолт `CURRENT_DATE`).
- **user_cards** — `id` (UUID картки, PK), `user_id` → `users(id)`
  `ON DELETE CASCADE`.
- **user_exclusions** — `id` (serial PK), `user_id` (FK, cascade),
  `start_datetime`, `stop_datetime` (timestamp), `type_exclusion`
  (`come later` | `leave earlier` | `full-time`).
- **time_log** — `user_id`, `date`, `start_time`, `stop_time`, `total_mins`,
  `is_late`, `is_leave`, `is_late_reason`, `is_leave_reason`; первинний ключ
  `(user_id, date)`, FK на `users(id)` з cascade. Прихід/відхід оновлюються
  через `INSERT ... ON CONFLICT (user_id, date) DO UPDATE`, а ознака приходу
  визначається за `xmax = 0`.

Усі дочірні таблиці видаляються каскадно разом із користувачем.

---

## Протокол та формат відповіді

Усі повідомлення (і HTTP, і AMQP) — JSON. Відповідь має єдиний конверт:

```json
{ "status": "ok", "response": { ... } }   // успіх із даними
{ "status": "ok" }                          // успіх без тіла
{ "status": "error", "message": "..." }     // помилка
```

---

## HTTP API

Слухач Cowboy піднімається на `cowboy_port` (за замовч. `8181`). Маршрут —
catch-all: будь-який `POST` із JSON-тілом, де **сам URL-шлях** є ключем
маршрутизації. Тіло — JSON, заголовок `content-type: application/json`.

| Метод | Шлях | Тіло (args) | Призначення |
|---|---|---|---|
| `POST` | `/user/create` | `user_name` | Створити користувача → `{id}`. |
| `POST` | `/user/delete` | `user_id` | Видалити користувача. |
| `POST` | `/user/list` | — | Список користувачів з очікуваним графіком. |
| `POST` | `/card/assign` | `card_uid`, `user_id` | Прив'язати картку до користувача. |
| `POST` | `/card/touch` | `card_uid` | Зафіксувати прихід/відхід → `event_type`. |
| `POST` | `/card/delete` | `card_uid` | Видалити картку. |
| `POST` | `/card/list_by_user` | `user_id` | Картки користувача. |
| `POST` | `/card/delete_all_by_user` | `user_id` | Видалити всі картки користувача. |
| `POST` | `/work_time/set` | `user_id`, `start_time`, `stop_time`, `days` | Задати графік. |
| `POST` | `/work_time/get` | `user_id` | Отримати графік. |
| `POST` | `/work_time/add_exclusion` | `user_id`, `type_exclusion`, `start_datetime`, `stop_datetime` | Додати виняток. |
| `POST` | `/work_time/get_exclusion` | `user_id` | Винятки користувача. |
| `POST` | `/work_time/history_by_user` | `user_id` | Журнал приходів/відходів. |
| `POST` | `/work_time/statistic_by_user` | `user_id`, `filter` | Агрегована статистика. |

Коди відповіді HTTP-handler-а:

| Код | Умова |
|---|---|
| `200` | Успіх. |
| `404` | `dispatch` повернув `{error, not_found}` (невідомий шлях). |
| `405` | Метод не `POST`. |
| `415` | Не вдалося декодувати тіло (непідтримуваний `content-type`). |
| `422` | Не пройдено валідацію. |
| `500` | Помилка БД або необроблений виняток. |

---

## RabbitMQ (RPC)

`time_tracker_mq_handler` — `gen_server`, що під час `init/1`:

- відкриває з'єднання та канал (`time_tracker_amqp`);
- оголошує **durable**-чергу `time_tracker_queue`;
- оголошує **topic**-exchange (`mq_exchange`, за замовч. `time_tracker_exchange`);
- прив'язує чергу з routing key `time_tracker_rk`;
- підписується на споживання з ручним `ack` (`no_ack = false`);
- моніторить процеси з'єднання й каналу — при падінні `gen_server` зупиняється
  й перезапускається супервізором.

Кожне вхідне повідомлення обробляється як **RPC**: шлях береться із заголовка
`method`, дані проходять той самий `validate → dispatch`, а результат
публікується назад у чергу з `reply_to`, зберігаючи `correlation_id`. Після
публікації повідомлення підтверджується (`basic.ack`).

---

## Валідація

`time_tracker_validator` використовує `liver`-схеми на кожен шлях. Кастомні
правила реєструються у `add_rules/0` (викликається при старті застосунку):

- `uuid` — формат UUID (8-4-4-4-12);
- `time` — час `HH:MM:SS` із перевіркою діапазонів;
- `iso_dt` — дата-час ISO-8601 `YYYY-MM-DDThh:mm:ss`.

Шляхи `/user/*` не мають окремої схеми — для них валідатор пропускає дані без
перевірки (`{ok, Data}`).

---

## Конфігурація

Наразі присутній лише `env/dev.config`. Фактичні ключі:

```erlang
{time_tracker_test, [
    {cowboy_port, 8181},
    {db_host, "localhost"}, {db_port, 5431},
    {db_user, "postgres"}, {db_password, "password"}
]}
```

Параметри RabbitMQ у конфіг не винесені — `time_tracker_amqp` бере їх з
оточення застосунку зі значеннями за замовчуванням: `mq_host` = `"localhost"`,
`mq_username` / `mq_password` = `<<"guest">>`, `mq_exchange` =
`<<"time_tracker_exchange">>`. Логування налаштоване через стандартний OTP
`logger` (файли `log/error.log`, `log/info.log` + консоль).

> `Makefile` очікує `env/$(CONFIG).config`, тож `make CONFIG=prod` спрацює лише
> після додавання відповідного `prod.config`.

---

## Збірка та запуск

Потрібні працюючі **Postgres** (за замовч. `localhost:5431`) та **RabbitMQ**
(`localhost:5672`). Перед першим запуском застосуйте схему:

```bash
psql -h localhost -p 5431 -U postgres -f db.sql
```

```bash
make                 # збірка dev-релізу (CONFIG=dev за замовчуванням)
make CONFIG=prod     # збірка prod-релізу у _rel/prod/ (потрібен env/prod.config)
./start.sh           # локальний запуск зі shell-ом та env/dev.config
```

`start.sh` запускає вузол напряму:

```bash
erl -pa deps/*/ebin ebin -config env/dev.config -s time_tracker_test_app -sname time_tracker_test
```

---

## Тестування

Автоматизованих тестів (EUnit/Common Test) у репозиторії наразі **немає**.
Доступні стандартні цілі erlang.mk:

```bash
make eunit       # модульні тести (коли з'являться)
make ct          # Common Test
make dialyzer    # статичний аналіз (DIALYZER_DIRS = ebin)
```

---

## Відомі обмеження

- Немає автентифікації/авторизації.
- Схема застосовується одним файлом [`db.sql`](db.sql); інструмента поетапних
  міграцій немає.
- Немає автоматизованих тестів.
- `time_tracker_work_time_api:delete_exclusion/1` реалізовано, але не
  під'єднано до `dispatch` і не має схеми валідації — наразі недосяжне.
- `time_tracker_db:query/2` відкриває нове з'єднання на кожен запит (без пулу).
- Параметри RabbitMQ не винесені в конфіг.
