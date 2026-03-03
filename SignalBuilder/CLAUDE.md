# Quantitative Strategy Designer — Project Guidelines

## Architecture: Model-View-Controller (MVC)

This project follows a strict MVC pattern using MATLAB packages. All source code lives in one of three package folders:

```
SignalBuilder/
├── CLAUDE.md
├── main.m                      % App entry point
├── +Model/                     % Business logic & data (Handle Classes)
│   ├── BaseModel.m
│   ├── MarketData.m
│   ├── Signal.m
│   ├── Strategy.m
│   └── Portfolio.m
├── +View/                      % UI & plotting (Value or Handle Classes)
│   ├── BaseView.m
│   ├── ChartView.m
│   └── StrategyView.m
└── +Controller/                % Mediates Model ↔ View
    ├── BaseController.m
    ├── DataController.m
    └── StrategyController.m
```

---

## Layer Responsibilities

### +Model  (Handle Classes — required)
- Contains **all** domain logic: data loading, signal generation, backtesting, portfolio calculations.
- Every class **must** inherit from `handle`. This ensures all controllers and views hold a shared reference — mutations are visible everywhere without copying data.
- The canonical time-series container is **`timetable`**. Raw OHLCV data, computed signals, equity curves, and any other time-indexed series must be stored as `timetable` fields.
- Model classes must **never** call any View code. Models are completely unaware of the UI.

### +View  (Value or Handle Classes)
- Responsible for all visual output: MATLAB figures, `uifigure` app panels, table display, export formatting.
- Views read data from Models via properties passed in by Controllers. Views **must not** mutate Model state directly.
- Chart helpers should accept a `timetable` and a column name — never raw arrays — to preserve time-axis metadata.

### +Controller  (Handle Classes recommended)
- Instantiates Models and Views, wires events/callbacks, and orchestrates data flow.
- A Controller calls Model methods to process data, then passes results to View methods for rendering.
- Controllers own the application lifecycle (open, close, refresh, export).

---

## Key Conventions

### Naming
| Artifact | Convention | Example |
|---|---|---|
| Package class | `PascalCase` | `MarketData`, `StrategyView` |
| Method | `camelCase` | `loadData()`, `computeSignal()` |
| Property | `camelCase` | `priceData`, `signalTable` |
| Private method/prop | `camelCase` with Access=private | — |
| Constants | `UPPER_SNAKE` | `MAX_LOOKBACK` |
| Script / entry point | `lower_snake` or `camelCase` | `main.m` |

### timetable Rules
- All time-series data is stored in `timetable`, never in plain matrices or tables with a separate date vector.
- Row times use `datetime` with explicit timezone (`'America/New_York'` for equities).
- Variable names in a timetable use `PascalCase` matching common financial conventions: `Open`, `High`, `Low`, `Close`, `Volume`, `Signal`, `Return`.
- Use `retime()` to align frequencies; avoid manual index arithmetic.
- Synchronise multi-asset timetables with `synchronize(..., 'union', 'fillwithconstant', NaN)`.

### Handle Class Rules
- All `+Model` classes inherit `< handle`.
- Override `delete()` for any class that opens files, timers, or external connections.
- Use `events` and `notify`/`addlistener` for loose coupling between Model and Controller (Observer pattern).
- Never store large `timetable` data in more than one place — pass handles, not copies.

### Error Handling
- Validate inputs with `arguments` blocks (R2019b+) in all public methods.
- Use `error('SignalBuilder:ClassName:errorID', msg, ...)` with package-qualified IDs.
- Wrap external data calls (file I/O, network) in `try/catch` and rethrow with context.

### Testing
- Unit tests live in `+Tests/` (a sibling package).
- Test classes extend `matlab.unittest.TestCase`.
- Each Model class has a corresponding test class: `+Tests/TestMarketData.m`, etc.
- Run all tests: `results = runtests('+Tests'); table(results)`.

---

## Workflow Rules for Claude

1. **Read before editing.** Never modify a class without reading it first.
2. **MVC boundaries are strict.** Do not add figure/plot calls inside `+Model`. Do not add domain logic inside `+View`.
3. **timetable first.** If a new time-indexed variable is needed, add it as a column to an existing `timetable` property rather than creating a parallel array.
4. **Handle class integrity.** Do not change a `+Model` class to `< matlab.mixin.Copyable` or remove `< handle` without explicit user approval.
5. **Minimal changes.** Fix or add exactly what is requested; do not refactor surrounding code.
6. **Confirm destructive operations.** Deleting properties, renaming public methods, or changing event signatures can break dependent code — confirm with the user first.
