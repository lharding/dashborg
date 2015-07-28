# END-OF-THE-WORLD NOTICE

As of this commit I've replaced this project in my own use with [tasknc](https://github.com/mjheagle8/tasknc). It's not likely there will be any further development here, but I'm leaving the repository up for posterity.

# HERE BE DRAGONS

This is dashborg, a PIM-dashboard tool I'm working on that uses taskwarrior as a task management backend. It's a bit barely functional at all right now and this repo mainly exists to ease my process of syncing development between different machines.

## Roadmap

- Explicit alerts for due or soon-to-be-due tasks
- More succint time-delta format (right now just using taskwarrior's)
- Pull upcoming events from google calendar and display in their own section
- notes section for non-task things
- "quick alarm" kitchen timer function

## WTF?

It's intended to be auto-shown when your clamshell device's lid has been closed long enough, so that it will be there waiting for you when you open it next. This roughly simulates the "agenda" lockscreen mode on old versions of BlackBerry OS.

## Yeah, but...*Lua?*

On my [Pandora](http://openpandora.org) a fresh Python VM is about 3600K, takes ~500ms to start, and maps 10MB of libraries, while a fresh Lua VM maps 5MB of libraries (mostly just glibc and friends), takes 1100K of live memory, and starts in under 50ms. Other interpreted languages compare similarly, and Lua is a relatively inoffensive language when compared with other things in its size class (e.g. bash). These numbers sound trivial as I type this on my reasonably powerful laptop, but on a constrained device like the pandora, they matter, and it's important that this too automatically launching not be the source of a zram heart attack.
