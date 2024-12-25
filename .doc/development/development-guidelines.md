# Coding guidelines

## Configuring Git's line ending handling

This cofniguration converts LF to CRLF when checking out in Windows systems and CRLF to LF when committing.

```sh
# Global Configuration: Applies the settings to all repositories on your system.
git config --global core.autocrlf true
```

```sh
# Local Configuration: Applies the settings only to the current repository.
git config core.autocrlf true
```


## Commit changes

It is recommended to use a linter for commit messages, which should be specified in the following format:

```sh
- [type] message
- [type] :icono: message
```

Example:

```sh
- commit -m [chore] add commitlinter
- commit -m [chore] :sparkles: add commitlinter (to commit with an icon, you can use [gitmoji](https://gitmoji.dev/))
```

The allowed standard types are:

```sh
- feat: A new feature for the user.
- fix: Fixes a bug that affects the user.
- perf: Changes that improve site performance.
- build: Changes in the build system, deployment tasks, or installation.
- ci: Changes in continuous integration.
- docs: Changes in documentation.
- refactor: Code refactoring such as variable or function name changes.
- style: Changes in formatting, tabs, spaces, or semicolons, etc.; do not affect the user.
- test: Adds tests or refactors an existing one.
- chore: Other changes that don't modify src or test files.
- revert: Reverts a previous commit.
```
