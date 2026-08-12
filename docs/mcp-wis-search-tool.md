# Задача: MCP-сервер пошуку по базі знань Mercedes WIS

## Контекст (передісторія, не потребує повторного дослідження)

У сусідньому проєкті `/home/max/pet/w245/teamwork` за один довгий сеанс було:
1. Побудовано корпус з ~7056 документів Mercedes WIS (repair manual), точно прив'язаних до 2 конкретних VIN власника (A150/W169 та B200/W245), через реверс-інжиніринг SQL-схеми WIS.
2. Залито весь корпус в OpenWebUI Knowledge Base з embedding-моделлю `BAAI/bge-base-en-v1.5` + reranker `cross-encoder/ms-marco-MiniLM-L-6-v2`, `TOP_K=50`, `TOP_K_RERANKER=10`, `CHUNK_SIZE=500`, `CHUNK_OVERLAP=75`.
3. Виявлено емпірично: якість відповіді через звичайний OpenWebUI-чат (з `auto`-моделлю OpenRouter) нестабільна — RAG інколи каже "не знайдено", хоча інформація фізично є в базі (перевірено вручну по кількох темах: масло, свічки — інформація є, чат сказав що немає; кондиціонер — інформації реально немає в WIS для цих авто, підтверджено окремим декомпіляційним дослідженням).
4. Висновок: цінність — у самому **корпусі** (унікальні, точно прив'язані до VIN документи), а не в наявному chat-пайплайні OpenWebUI, який непередбачувано фільтрує/переформульовує знайдене через LLM.
5. Ідея власника: підключити пошук по цій базі знань **напряму як інструмент** — і до OpenWebUI (де він уже є, як RAG), і до Claude Code (де його зараз немає) — щоб AI-агент сам робив запит і сам оцінював релевантність знайденого, без проміжної недовірливої LLM-прошарки.

## Що вже є в кластері (не створювати заново)

`workload/mcpo.tf` — вже розгорнутий `mcpo` (офіційний `ghcr.io/open-webui/mcpo:main`, MCP→OpenAPI проксі для OpenWebUI). Конфіг MCP-серверів — `kubernetes_config_map.mcpo_config`, поле `data["config.json"]`, формат:
```json
{"mcpServers": {"<name>": {"command": "...", "args": [...], "env": {...}}}}
```
mcpo запускає кожен сервер як дочірній процес (stdio MCP transport) і виставляє його як OpenAPI на `mcpo.kms-lab.in.ua/<name>/...`. Зараз там 3 сервери (kubernetes, prometheus, github), усі через `npx`.

**Важлива перевірена деталь:** контейнер `mcpo` вже містить:
- `/app/.venv/bin/python3` з **уже встановленим пакетом `mcp`** (офіційний Python MCP SDK, той самий, яким сам mcpo під капотом і побудований) — тобто наш сервер можна писати на Python **без встановлення жодних нових залежностей у цьому контейнері**.
- `stdlib urllib.request` — досить для HTTP-викликів до OpenWebUI API, без потреби в `requests`.
- Node 22 / npx 10 теж є, якщо зрештою обрати JS — але Python явно простіший шлях тут.

## Джерело даних: OpenWebUI Retrieval API

- Базовий URL: `https://openui.kms-lab.in.ua`
- API-ключ: `/home/max/pet/w245/teamwork/.secrets/openwebui_api_key` (читати з файлу, не хардкодити)
- ID бази знань: `/home/max/pet/w245/teamwork/.secrets/openwebui_knowledge_id` (Читати з файлу — може змінитись, якщо базу колись перестворять)
- Ендпоінт пошуку (безкоштовний, без виклику LLM, чистий vector search — **не застосовує reranker**, це підтверджено емпірично сьогодні):
  ```
  POST /api/v1/retrieval/query/collection
  Authorization: Bearer <api_key>
  Content-Type: application/json

  {"collection_names": ["<knowledge_id>"], "query": "<текст запиту>", "k": 20}
  ```
  Відповідь: `{"distances": [[...]], "documents": [["текст чанка", ...]], "metadatas": [[{"name": "ar0510p7601ak.md", "source": "...", ...}, ...]]}` — усі три масиви одного порядку/довжини, k елементів.

  Дистанція — cosine distance (нижче = ближче/релевантніше), але в цьому корпусі діапазон стиснутий (~0.80-0.94 для більшості запитів), тому абсолютне значення малоінформативне саме по собі — важливіший відносний порядок і сам вміст.

- Rерanking НЕ застосовується цим ендпоінтом. Якщо потрібна якість, порівнянна з тим, що бачить чат (з reranker), доведеться або (а) прийняти це обмеження й просто брати більший `k` (перевірено: `k=50` дає прийнятний результат), або (б) дослідити чи є в OpenWebUI окремий rerank-only ендпоінт (не досліджено сьогодні, не факт що існує окремо від повного chat completion пайплайну).

## Структура документів у базі

- Кожен чанк має `metadata.name` = ім'я файлу в форматі `<doc_id_без_крапок_дефісів_нижнім_регістром>.md`, напр. `AR05.10-P-7601AK` → `ar0510p7601ak.md`.
- Оригінальні markdown-файли (для довідки, не для читання агентом під час виконання — просто контекст) лежать у `/home/max/pet/w245/teamwork/data/output/<doc_id>/<doc_id>.md`, з YAML frontmatter (`vehicles: [VIN...]`, `models: "..."` тощо).
- Корпус охоплює: процедури ремонту, коди несправностей (DTC), специфікації, графіки ТО — **саме для 2 конкретних авто власника**, не загальний Mercedes.
- Відомий пробіл: діагностика кондиціонера (AD83.xx) для цієї платформи в WIS відсутня фізично — це не баг retrieval, а реальна відсутність даних (досліджено окремим агентом сьогодні, декомпіляцією серверного коду WIS).

## Завдання

### 1. Написати MCP-сервер (Python, stdio transport)

Файл-кандидат: `/home/max/pet/w245/teamwork/mcp-servers/wis_search.py` (класти в teamwork-репо, не в IaaC — це стосується корпусу, логічно тримати поруч; IaaC лише монтує/запускає копію).

Один інструмент:
- Ім'я: `search_mercedes_wis`
- Параметри: `query` (string, обов'язковий), `k` (integer, опційний, default 20, розумна межа напр. 50)
- Дія: HTTP POST на `/api/v1/retrieval/query/collection` як описано вище, з ключем і knowledge_id з файлів у `.secrets/`
- Повертає: для кожного результату — ім'я файлу (doc_id), дистанція, повний текст чанка (чанки вже невеликі, CHUNK_SIZE=500, можна повертати без обрізання)
- Без побічних ефектів, чисто read-only

Використати офіційний `mcp` Python SDK (`pip install mcp` локально для тестування; у контейнері mcpo він уже є). Референс: https://github.com/modelcontextprotocol/python-sdk — низькорівневий `Server` клас або high-level `FastMCP`, обидва підійдуть, `FastMCP` простіший.

**Протестувати локально перед розгортанням** — напр. через `mcp dev wis_search.py` (SDK CLI) або прямим stdio-викликом, впевнитись що `tools/list` і `tools/call` коректно відповідають на реальний запит (напр. query="engine oil filling capacity", звірити що результат схожий на те, що ми сьогодні бачили вручну через curl).

### 2. Підключити до mcpo (Terraform)

У `workload/mcpo.tf`:
- Додати новий запис у `mcpServers` в `kubernetes_config_map.mcpo_config`:
  ```json
  "wis-search": {
    "command": "/app/.venv/bin/python3",
    "args": ["/app/custom/wis_search.py"],
    "env": {
      "OPENWEBUI_API_KEY_FILE": "/app/custom/openwebui_api_key",
      "OPENWEBUI_KB_ID_FILE": "/app/custom/openwebui_knowledge_id"
    }
  }
  ```
  (або передати значення напряму як env-змінні замість файлів — простіше, але тоді секрет опиниться в ConfigMap як plaintext; краще завести окремий `kubernetes_secret` для API-ключа, за аналогією з `mcpo_github_token`, і змонтувати його поруч зі скриптом).
- Додати новий `kubernetes_config_map` (напр. `mcpo_wis_search_script`) з вмістом `wis_search.py` як `data`, змонтувати в контейнер `mcpo` за шляхом `/app/custom/` (новий `volume_mount` + `volume`, за зразком існуючого `config-volume`).
- Додати `kubernetes_secret` для `openwebui_api_key` (значення взяти з `/home/max/pet/w245/teamwork/.secrets/openwebui_api_key` — це не Bitwarden-секрет, локальний, тому просто `random`/`sensitive` variable або читання файлу через `file()` в Terraform, обережно не закомітити значення в git).

**Дотримуватись усталеної практики цієї інфраструктури: усі зміни кластера — лише через Terraform, без прямих `kubectl apply`/`kubectl patch`.** Сьогодні неодноразово траплялись проблеми саме коли хтось намагався патчити напряму.

### 3. Підключити до Claude Code (мене) напряму

Окремо від mcpo — Claude Code вміє підключати MCP-сервери напряму через stdio (`.mcp.json` в проєкті або `claude mcp add`). Оскільки скрипт лежить локально (`/home/max/pet/w245/teamwork/mcp-servers/wis_search.py`), можна зареєструвати його як **окремий, незалежний від mcpo/кластера** MCP-сервер — просто `command: "python3", args: ["/home/max/pet/w245/teamwork/mcp-servers/wis_search.py"]` в конфізі Claude Code для цього проєкту. mcpo й Claude Code кожен запускає СВОЮ копію того самого скрипта як дочірній процес — це нормальна модель роботи stdio MCP-серверів, не потрібен спільний "сервіс".

Для цього знадобиться `pip install mcp` в `/home/max/pet/w245/teamwork/.venv` (локально, не в контейнері — там уже є).

### 4. Перевірка

- `mcpo` даватиме OpenAPI-документацію на `https://mcpo.kms-lab.in.ua/wis-search/docs` (типова поведінка mcpo для кожного підключеного сервера) — перевірити, що інструмент `search_mercedes_wis` там видно і викликається.
- В OpenWebUI: підключити `mcpo`-експортований інструмент до моделі (Workspace → Tools), протестувати запитом типу "яка процедура заміни ланцюга ГРМ" — порівняти результат з тим, що RAG видає зараз.
- З Claude Code: після реєстрації MCP-сервера — перевірити, що інструмент з'являється і повертає розумні результати на тестовий запит.

## Обмеження

- Тільки читання, жодних записів у OpenWebUI/базу знань.
- Не займатись покращенням якості retrieval (reranking, chunk-тюнінг) в межах цієї задачі — це вже зроблено сьогодні на стороні OpenWebUI-конфіга, тут просто підключення нового каналу доступу до того самого API.
- Не чіпати існуючі mcpo-сервери (kubernetes/prometheus/github).

## Оновити TODO.md

Пункт "Open WebUI: Cross-lingual RAG & Vector Search Optimization" — значною мірою вже виконано в teamwork-сесії (embedding-модель замінено на `bge-base-en-v1.5`, додано reranker, підвищено `TOP_K`, зменшено `CHUNK_SIZE`, повний reindex зроблено). Пункт "Prompt Translation & Enhancement Adapter" — фільтр `ukrainian_to_english_prompt_enhancer` уже існує в системі (можливо, зроблений раніше іншою сесією) — вартий перевірки, чи actively enabled, і чи не має бути перепризначений на `openrouter/auto` замість `openrouter/free` (сьогодні `free`-модель показала зламаний/непослідовний вивід в кількох тестах).
