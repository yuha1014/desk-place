# DeskPlace

DeskPlace is a native macOS app that displays a selected HTML file across the full display, with focus, clock, notes, and task panels. It uses a normal macOS window so physical mouse input works; uncovered areas pass input through to the selected HTML. Other application windows can cover DeskPlace when they become active, so it does not occupy macOS's protected desktop-icon layer.

## Run

Building the Mac app requires the macOS Command Line Tools (`swiftc`, `codesign`, and `hdiutil`). It does not download npm packages.

```sh
npm run dist:mac
```

The build always creates `dist/DeskPlace-0.1.4-arm64.pkg` and attempts to create `dist/DeskPlace-0.1.4-arm64.dmg`. The package installs DeskPlace into `/Applications`; the DMG is a drag-to-Applications disk image. In this environment, macOS denied disk-image attachment, so only the package was produced. To build and open the app in one step, run `npm run dev`. After building, `npm start` opens the app.

The app keeps focus text, notes, tasks, panel positions, and selected HTML path locally. Closing the window does not clear them. The HTML file's own styles determine its design; DeskPlace stretches its document canvas to the full display. No online fonts are used by DeskPlace itself.

## Current features

- Editable daily focus and notes with automatic local saving
- Add, rename (double-click a task), complete, and delete tasks
- Drag panel headers to move panels; positions are saved
- macOS login item toggle in settings
- Optional keep-awake mode prevents display and system idle sleep while DeskPlace is visible; use a power adapter for long sessions
- Select an HTML file as the full-screen desktop background using **배경 HTML 선택**, `파일 > HTML 파일 열기`, or macOS **Open With**
- Show the selected HTML across the display in a normal, interactive app window
- Restore the built-in background from settings
- Move focus, clock, notes, and task panels by dragging each panel's heading; positions persist
- Scroll long HTML backgrounds with the trackpad over uncovered background areas
- Scale the imported HTML from 50% to 150%; the surrounding area uses its solid CSS background color
- Hide or show the four panels and resize each from settings; preferences persist locally
- Route physical mouse input through the transparent control layer to the selected HTML except where an interactive DeskPlace panel is visible
- **바탕화면 보기** hides other apps and DeskPlace on macOS
- Live clock and date
- Responsive stacked layout on narrower windows

## Notes

The login item switch and the hide-other-apps desktop action are supported on macOS. The installer registers `.html`/`.htm` as an alternate Open With option. The app is ad-hoc signed locally, but is not Developer ID signed or notarized; macOS may require **Open Anyway** in Privacy & Security the first time. The selected file can use its normal HTML, CSS, and browser JavaScript, without Node.js access. Signing/notarization, a custom app icon, multiple notes/projects, and JSON backup are future work.
