# minecraft_opencomp

Рабочая директория для программирования на Lua 5.3 под мод Minecraft **OpenComputers**.

- Правила и конвенции — [CLAUDE.md](CLAUDE.md)
- Локальный API-конспект — [docs/oc_cheatsheet.md](docs/oc_cheatsheet.md)
- Официальная документация — https://ocdoc.cil.li/

Структура:

```
programs/   точки входа для OpenOS
lib/        модули под require
eeprom/     прошивки EEPROM
docs/       заметки
```

Код локально не запускается — пишется здесь, исполняется в игре. Локально доступны только `luac -p` (синтаксис) и `luacheck` (линт).

---

## Установка загрузчика `pull` на машину OC

На свежей машине OpenOS (нужна **internet card**) один раз выполни:

```
wget https://raw.githubusercontent.com/1Boop2/mc-opencomp/main/programs/pull.lua /bin/pull.lua
```

После этого `pull <имя>` тянет любой скрипт из `programs/` репозитория и запускает.

> **Важно:** `wget` в OpenOS не перезаписывает существующие файлы (флаг `-f` он игнорирует). Если `/bin/pull.lua` уже есть и его нужно обновить — используй `pull --self-update` (он использует `io.open("w")` и нормально перезаписывает). На крайний случай — `rm /bin/pull.lua` перед `wget`.

**Использование:**

| Команда | Что делает |
|---------|-----------|
| `pull <name> [args...]` | скачать (или из кеша) и запустить |
| `pull --update <name>` | принудительно обновить из сети |
| `pull --list` | что лежит в кеше (`/home/.pull_cache/`) |
| `pull --self-update` | обновить сам `pull.lua` в `/bin` |

**Smoke-тест:** `pull _example один два три` → должен распечатать приветствие, uptime и переданные аргументы.

**Конфигурация:** имя репозитория и ветка зашиты в начале `programs/pull.lua` (константы `REPO`, `BRANCH`, `PREFIX`).
