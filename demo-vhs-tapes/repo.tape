Output demo-vhs-gifs/repo.gif

Set Padding 0
Set Framerate 10

Set Width  1024
Set Height  768
Set FontSize 15

Set TypingSpeed 100ms

Type@50ms "docfd --cache-dir .cache *.md # Using a local cache for the demo."
Sleep 1s
Enter

Sleep 1s

Type "j"
Sleep 1s
Type "j"
Sleep 1s

Type "/"
Type "fuzz search"
Enter
Sleep 1s

Type "J"
Sleep 1s

Tab
Sleep 1s

Type "J"
Sleep 1s

Enter
Sleep 1s
Type "O"
Type@50ms "Docfd opens the editor to where the search result is when we hit Enter."
Escape
Sleep 2s
Type@200ms ":q!"
Enter

Sleep 2s
