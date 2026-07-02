<p align="center">
  <img src="assets/banner.svg" alt="obsidian-tasks.nvim" width="100%">
</p>

<p align="center">
  Управление задачами из одного или нескольких Obsidian vault прямо в Neovim.<br>
  Markdown остаётся единственным источником данных.
</p>

<p align="center">
  <a href="README.md">English</a> · <a href="FUTURE.md">Планы развития</a>
</p>

## Возможности

- несколько todo-файлов в одном представлении или отдельных tabpage;
- floating window размером 50% × 50% либо обычное окно;
- вложенная группировка по порядку тегов;
- toggle через `<Space>` с датой `✅ YYYY-MM-DD`;
- пошаговое создание задачи с выбором репозитория, тегов и дат;
- переход к исходной Markdown-строке через `<CR>`;
- фильтры `active`, `done`, `all`;
- безопасная запись без обязательных зависимостей.

## Установка через lazy.nvim

```lua
{
  "jjuchara/obsidian-tasks.nvim",
  opts = {
    repositories = {
      {
        name = "personal",
        path = "~/obsidian/personal/Tasks.md",
      },
      {
        name = "work",
        vault = "~/obsidian/work",
        todo_file = "Projects/Tasks.md",
      },
    },
    view = {
      type = "float",                 -- "float" | "window"
      width = 0.5,
      height = 0.5,
      close_on_leave = true,
      repository_mode = "sections",  -- "sections" | "tabs"
      status = "active",             -- "active" | "done" | "all"
    },
    mappings = {
      open = "<leader>to",
      create = "<leader>ta",
    },
  },
}
```

Можно передать прямой `path` к todo-файлу либо пару `vault + todo_file`.

## Управление

| Команда или клавиша | Действие |
|---|---|
| `:ObsidianTasks` | Открыть задачи |
| `:ObsidianTasksCreate` | Создать задачу |
| `:ObsidianTasksRefresh` | Перечитать открытые представления |
| `<Space>` | Переключить checkbox |
| `<CR>` | Открыть исходный Markdown |
| `s` | Переключить `active → done → all` |
| `r` | Обновить данные |
| `q`, `<Esc>` | Закрыть представление |

Floating window автоматически закрывается при переходе в другое окно. Для постоянного float задайте `view.close_on_leave = false`.

## Создание задачи

Плагин последовательно спрашивает репозиторий, текст, основной тег, дополнительные теги, дату начала и дедлайн. Дополнительные теги можно вводить как `gantt urgent`, `#gantt #urgent` или `gantt, urgent`.

## Формат и группировка

```markdown
## #work

- [ ] Выпустить версию #work #frontend #urgent 📅 2026-07-10
```

Порядок тегов задаёт дерево `#work → #frontend → #urgent`. Если inline-тегов нет, используется ближайший заголовок `## #tag`. YAML frontmatter и fenced code blocks игнорируются.

Полный список настроек находится в [английском README](README.md#configuration), а встроенная справка доступна через `:help obsidian-tasks`.
