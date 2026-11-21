# Workspace demo

A 20.5-second HyperFrames composition for the Shiftland website. It follows the example branch `fix/empty-state` from editing a task list to reviewing the change in a browser. The SwiftUI bar images show actual Shiftland controls with example apps and workspace assignments. The desktop uses staged windows, native macOS icons, and an original ImageGen coastline wallpaper.

- [index.html](index.html) sets the canvas and scene timing.
- [compositions/workspace-switch.html](compositions/workspace-switch.html) contains the desktop and the four shortcut-driven actions.
- [compositions/end-card.html](compositions/end-card.html) contains the hare and wordmark.
- [film.css](film.css) styles the film's captions, keycaps, and end card.
- [desktop.css](desktop.css) styles the desktop, menu bar, Dock, and sample windows.
- [Dimly lit](https://opengameart.org/content/dimly-lit) by iamoneabe is the instrumental bed. The [CC0 1.0 dedication](https://creativecommons.org/publicdomain/zero/1.0/) covers the source. The local MP3 is a 20.5-second excerpt starting at 18.015 seconds, with fades and level normalization.

Run these commands from this directory with Node.js 22+, FFmpeg, and `cwebp` installed.

```sh
npx hyperframes@0.9.77 check
npx hyperframes@0.9.77 preview
```

After reviewing the timeline, export the website files.

```sh
mkdir -p ../.build
npx hyperframes@0.9.77 render --quality delivery --workers 2 -o ../.build/workspace-demo-master.mp4
ffmpeg -i ../.build/workspace-demo-master.mp4 -c:v libx264 -crf 20 -pix_fmt yuv420p -c:a aac -b:a 128k -movflags +faststart ../web/assets/workspace-demo.mp4
ffmpeg -ss 4.3 -i ../.build/workspace-demo-master.mp4 -frames:v 1 -vf scale=1600:-2 ../.build/workspace-poster.png
cwebp -q 85 ../.build/workspace-poster.png -o ../web/assets/workspace-demo.webp
```

When replacing the generated files, add `-y` to the FFmpeg commands to overwrite the previous exports. The website serves the MP4 and poster directly from `web/assets/`.
