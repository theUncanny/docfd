# Docfd
TUI multiline fuzzy document finder

Think interactive grep for both text files and PDFs,
but word/token based instead of regex and line based,
so you can search across lines easily.

Docfd aims to provide good UX via integration with common text editors
and PDF viewers,
so you can jump directly to a search result with a single key press.

---

Navigating repo:

![](demo-vhs-gifs/repo.gif)

---

Navigating "OCaml Programming: Correct + Efficient + Beautiful" book PDF
and opening it to the closest location to the selected search result via PDF viewer integration:

![](screenshots/pdf-viewer-integration.jpg)

## Features

- Multithreaded indexing and searching

- Multiline fuzzy search of multiple files or a single file

- Swap between multi-file view and single file view on the fly

- Content view pane that shows the snippet surrounding the search result selected

- Text editor and PDF viewer integration

## Installation

Statically linked binaries are available via
[GitHub releases](https://github.com/darrenldl/docfd/releases)

Docfd is also packaged on:

- [AUR](https://aur.archlinux.org/packages/docfd-bin) by [kseistrup](https://github.com/kseistrup)

**Notes for packagers**: Outside of the OCaml toolchain for building (if you are
packaging from source), Docfd also requires the following
external tools at run time for full functionality:

- `pdftotext` from `poppler-utils` for PDF support

- `fzf` for file selection menu if user requests it

## Integration details

<details>

#### Text editor integration

Docfd uses the text editor specified by `$VISUAL` (this is checked first) or `$EDITOR`.

Docfd opens the file at first line of search result
for the following editors:

- `nano`
- `nvim`/`vim`/`vi`
- `kak`
- `hx`
- `emacs`
- `micro`
- `jed`/`xjed`

#### PDF viewer integration

Docfd guesses the default PDF viewer based on the output
of `xdg-mime query default application/pdf`,
and invokes the viewer either directly or via flatpak
depending on where the desktop file can be first found
in the list of directories specified by `$XDG_DATA_DIRS`.

Docfd opens the file at first page of the search result
and starts a text search of the most unique word
of the matched phrase within the same page
for the following viewers:

- okular
- evince
- xreader
- atril

Docfd opens the file at first page of the search result
for the following viewers:

- mupdf

</details>

## Launching

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
files with one of the following extensions by default:

- `.txt`
- `.md`
- `.pdf`

You can change the file extensions to use via `--exts`,
or add onto the list of extensions via `--add-exts`.

<details>

If the list of paths is empty,
then Docfd defaults to scanning the
current directory `.`.

If any of the file ends with `.pdf`, then `pdftotext`
is required to continue.

If exactly one file is specified
in the list of paths, then Docfd uses **Single file view**.
Otherwise, Docfd uses **Multi-file view**.

If any of the path is `?`, then file selection
of the discovered files
via `fzf`
is invoked.

</details>

## Searching

The search field takes a search expression as input. A search expression is
one of:

- Search phrase, e.g. `fuzzy search`
- `(expression)`
- `expression | expression` (or), e.g. `go to ( left | right )`

<details>

#### Search phrase and search procedure

Document content and user input in the search field are tokenized/segmented
in the same way, based on:
- Contiguous alphanumeric characters
- Individual symbols
- Individual UTF-8 characters
- Spaces

A search phrase is a list of said tokens.

Search procedure is a DFS through the document index,
where the search range for a word is fixed
to a configured range surrounding the previous word (when applicable).

A token in the index matches a token in the search phrase if they are:
- A case-insensitive exact match
- Or a case-insensitive substring match (token in search phrase being the substring)
- Or within the configured case-insensitive edit distance threshold

Search results are then ranked using heuristics.

</details>

## Multi-file view

![](screenshots/main0.png)

![](screenshots/main1.png)

The default TUI is divided into four sections:
- Left is the list of documents which satisfy the search phrase
- Top right is the content view of the document which tracks the search result selected
- Bottom right is the ranked search result list
- Bottom pane consists of:
    - Status bar
    - Key binding info
    - File content requirement field
    - Search field

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
- Scroll down the search result list
    - `Shift`+`J`
    - `Shift`+Down arrow
    - `Shift`+Page down
    - Scroll down with mouse wheel when hovering above the area
- Scroll up the document list
    - `Shift`+`K`
    - `Shift`+Up arrow
    - `Shift`+Page up
    - Scroll up with mouse wheel when hovering above the area
- Open document
    - `Enter`
        - Docfd tries to use `$VISUAL` first, if that fails then Docfd tries `$EDITOR`
- Switch to single file view
    - `Tab`
- Switch to `Require content` mode
    - `?`
- Switch to `Search` mode
    - `/`
- Clear search phrase
    - `x`
- Exit Docfd
    - `Esc`, `Ctrl+C` or `Ctrl+Q`

`Search` mode
- Search field is active in this mode
- `Enter` to confirm search phrase and exit the mode

`Require content` mode
- Required content field is active in this mode
- `Enter` to confirm file content requirements and exit the mode

</details>

#### File content requirements

<details>

The required content field accepts a content requirement expression.

A content requirement expression is one of:
- Search phrase
- `(expression)`
- `expression & expression`
- `expression | expression`

Note that the edit distance is not considered here.
Only case-insensitive exact matches or substring matches against
the search phrases are considered.

In other words, given the same phrase,
it is treated less fuzzily as a content requirement expression
compared to being used as a search phrase in the search field.

</details>

## Single file view

If the specified path to Docfd is not a directory, then single file view
is used.

![](screenshots/single-file0.png)

![](screenshots/single-file1.png)

In this view, the TUI is divided into only two sections:
- Top is ranked search result list
- Bottom is the search interface

#### Controls

<details>

The controls are simplified in single file view,
namely `Shift` is optional for scrolling through search result list.

`Navigation` mode
- Scroll down the search result list
    - `j`
    - Down arrow
    - Page down
    - `Shift`+`J`
    - `Shift`+Down arrow
    - `Shift`+Page down
    - Scroll down with mouse wheel when hovering above the area
- Scroll up the document list
    - `k`
    - Up arrow
    - Page up
    - `Shift`+`K`
    - `Shift`+Up arrow
    - `Shift`+Page up
    - Scroll up with mouse wheel when hovering above the area
- Open document
    - `Enter`
        - Docfd tries to use `$VISUAL` first, if that fails then Docfd tries `$EDITOR`
- Switch to multi-file view
    - `Tab`
- Switch to `Search` mode
    - `/`
- Clear search phrase
    - `x`
- Exit Docfd
    - `Esc`, `Ctrl+C` or `Ctrl+Q`

`Search` mode
- Search field is active in this mode
- `Enter` to confirm search phrase and exit search mode

</details>

## Limitations

- File auto-reloading is not supported for PDF files,
  as PDF viewers are invoked in the background via shell.
  It is possible to support this properly
  in the ways listed below, but requires
  a lot of engineering for potentially very little gain:

    - Docfd waits for PDF viewer to terminate fully
      before resuming, but this
      prohibits viewing multiple search results
      simultaneously in different PDF viewer instances.

    - Docfd manages the launched PDF viewers completely,
      but these viewers are closed when Docfd terminates.

    - Docfd invokes the PDF viewers via shell
      so they stay open when Docfd terminates.
      Docfd instead periodically checks if they are still running
      via the PDF viewers' process IDs,
      but this requires handling forks.

    - Outside of tracking whether the PDF viewer instances
      interacting with the files are still running,
      Docfd also needs to set up file update handling
      either via `inotify` or via checking
      file modification times periodically.

## Acknowledgement

- Demo gifs are made using [vhs](https://github.com/charmbracelet/vhs).
