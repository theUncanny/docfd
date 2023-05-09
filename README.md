# Docfd
TUI fuzzy document finder

## Installation

Statically linked binaries are available via
[GitHub releases](https://github.com/darrenldl/docfd/releases)

## Features

- Multithreaded indexing and searching

- Multiline fuzzy search of multiple files or a single file

- Swap between multi file view and single file view on the fly

- Content view pane that shows the snippet surrounding the search result selected

## Usage

#### Read from piped stdin

```
command | docfd
```

Docfd uses **Single file view**
when source of document is piped stdin.

Files specified as arguments to docfd are ignored
in this case.

#### Read from files

```
docfd [PATH...]
```

The list of paths can contain directories.
Each directory in the list is scanned recursively for
files with one of the following extensions:

- `.md`
- `.txt`

If the list of paths is empty,
then Docfd defaults to scanning the
current directory `.`.

If exactly one file is specified
in the list of paths, then Docfd uses **Single file view**.
Otherwise, Docfd uses **Multi file view**.

## Multi file view

Searching `single pipe stdn` in repo root:
![](screenshots/main0.png)

Searching `[github]` in repo root:
![](screenshots/main1.png)

The default TUI is divided into four sections:
- Left is the list of documents which satisfy the search constraints
- Top right is the content view of the document which tracks the search result selected
- Bottom right is the ranked content search result list
- Bottom pane consists of the status bar, key binding info, and search field

#### Controls

<details>

Docfd operates in modes, the initial mode is `Navigation` mode.

`Navigation` mode
- Scroll down the document list
  - `j`
  - Down arrow
  - Page down
  - Scroll down with mouse wheel when hovering above the area
- Scroll up the document list
  - `k`
  - Up arrow
  - Page up
  - Scroll up with mouse wheel when hovering above the area
- Scroll down the content search result list
  - `Shift`+`j`
  - `Shift`+Down arrow
  - `Shift`+Page down
  - Scroll down with mouse wheel when hovering above the area
- Scroll up the document list
  - `Shift`+`k`
  - `Shift`+Up arrow
  - `Shift`+Page up
  - Scroll up with mouse wheel when hovering above the area
- Open document
  - `Enter`
    - Docfd tries to use `$VISUAL` first, if that fails then Docfd tries `$EDITOR`
- Switch to single file view
  - `Tab`
- Switch to `Search` mode
  - `/`
- Clear search phrase
  - `x`
- Exit Docfd
  - `q` or `Ctrl+c`

`Search` mode
- Search field is active in this mode
- `Enter` to confirm search phrase and exit search mode

</details>

## Single file view

If the specified path to Docfd is not a directory, then single file view
is used.

Searching `single pipe stdn` in `README.md`:
![](screenshots/single-file0.png)

Searching `[github]` in `README.md`:
![](screenshots/single-file1.png)

In this mode, the TUI is divided into only two sections:
- Top is ranked content search result list
- Bottom is the search interface

#### Controls

<details>

The controls are simplified in single file view,
namely `Shift` is optional for scrolling through search result list.

`Navigation` mode
- Scroll down the content search result list
  - `j`
  - Down arrow
  - Page down
  - `Shift`+`j`
  - `Shift`+Down arrow
  - `Shift`+Page down
  - Scroll down with mouse wheel when hovering above the area
- Scroll up the document list
  - `k`
  - Up arrow
  - Page up
  - `Shift`+`k`
  - `Shift`+Up arrow
  - `Shift`+Page up
  - Scroll up with mouse wheel when hovering above the area
- Open document
  - `Enter`
    - Docfd tries to use `$VISUAL` first, if that fails then Docfd tries `$EDITOR`
- Switch to multi file view
  - `Tab`
- Switch to `Search` mode
  - `/`
- Clear search phrase
  - `x`
- Exit Docfd
  - `q` or `Ctrl+c`

`Search` mode
- Search field is active in this mode
- `Enter` to confirm search phrase and exit search mode

</details>
