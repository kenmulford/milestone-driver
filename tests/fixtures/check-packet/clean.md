Issue: #1
Base: __BASE__
Worktree: __WORKTREE__

## Files

| Path | Change |
|---|---|
| src/app.md | edit |
| new/file.md | new |

## Edit points

### src/app.md (alpha anchor line)

```text
alpha anchor line
```

becomes

```text
alpha anchor line, edited
```

### new/file.md (new)

```markdown
# New file

### Foo (bar)
## Rules
```

## Calls

### src/app.md (beta helper line)

```text
beta helper line
```

## Tests

A quoted markdown test body, whose headings are fenced and never checked:

```markdown
### Foo (bar)
## Rules
```

## Rules

none

## Verified facts

none

## Decisions

none

## Verify

none

## Out of scope

none
