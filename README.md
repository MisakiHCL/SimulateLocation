# SimulateLocation

Interactive iPhone-to-Xcode location simulation without hand-editing GPX files.

[简体中文](README.zh-CN.md)

SimulateLocation is an iOS companion app plus a small Mac bridge. The iPhone app lets you pick a location on Apple Maps, then the Mac bridge writes the selected coordinate into a GPX file and tries to apply it to Xcode's active location simulation workflow.

## Features

- Pick any location directly on Apple Maps.
- Center and select the phone's real current location.
- Discover the Mac bridge automatically over Bonjour.
- Use the optional macOS menu bar controller to start/stop the bridge without keeping a terminal open.
- Generate a stable `Generated/SelectedLocation.gpx` file for Xcode.
- Keep timestamped GPX history under `Generated/History/`.
- Apply coordinates to booted iOS simulators through `simctl location set`.
- Try to switch Xcode's `Debug > Simulate Location` menu automatically.
- Convert between WGS84 and GCJ-02 in mainland China so the map marker, phone blue dot, and GPX output stay aligned.

## Requirements

- macOS with Xcode installed.
- An iPhone running the app, or an iOS simulator for development.
- iPhone and Mac on the same local network when using a physical device.
- Local Network permission for the iOS app.
- Accessibility permission for Xcode menu automation on macOS.

## Quick Start

Recommended menu bar flow:

1. Build the menu bar app:

   ```bash
   ./Scripts/build-menu-bar-app
   ```

2. Open the built app:

   ```bash
   open Build/SimulateLocationMenuBar.app
   ```

3. From the menu bar item, choose **Start**. This starts `Scripts/location-bridge` and opens the Xcode project.
4. In Xcode, select the `SimulateLocation` scheme and choose your iPhone as the run destination.
5. Configure your development team in `Signing & Capabilities`.
6. Run the iPhone app.
7. Allow Local Network access on the iPhone when prompted.
8. Wait until the app shows that the Mac bridge is connected.
9. Tap a location on the map, then tap **Apply Automatically**.

Manual command-line flow:

1. Start the Mac bridge:

   ```bash
   ./Scripts/location-bridge
   ```

2. Open `SimulateLocation.xcodeproj` in Xcode.
3. Select your iPhone as the run destination.
4. Configure your development team in `Signing & Capabilities`.
5. Run the app.
6. Allow Local Network access on the iPhone when prompted.
7. Wait until the app shows that the Mac bridge is connected.
8. Tap a location on the map, then tap **Apply Automatically**.

## Menu Bar Controller

The `SimulateLocationMenuBar` macOS target provides three actions:

- **Start**: starts the bridge on the default port, resolves port conflicts, and opens `SimulateLocation.xcodeproj`.
- **Stop**: stops the active bridge.
- **Quit**: stops the active bridge, then exits the menu bar app.

The menu also shows the current bridge status. If the default port is already used by an old SimulateLocation bridge, it is stopped automatically. If another process owns the port, the controller asks whether to force close it or use the next available port. Quitting the controller does not force-quit Xcode.

`Scripts/build-menu-bar-app` creates `Build/SimulateLocationMenuBar.app`. The `Build/` directory is local output and is not tracked by Git.

## Mac Bridge

The bridge listens on `0.0.0.0:8765` by default and advertises `_location-gpx._tcp.` over Bonjour.

Generated files:

- `Generated/SelectedLocation.gpx`: stable GPX file used by Xcode's location simulation menu.
- `Generated/History/SelectedLocation_MM-dd_HH:mm.gpx`: timestamped history file for each apply action.
- `Generated/latest.json`: latest coordinate metadata, ignored by Git.

Useful options:

```bash
./Scripts/location-bridge --port 8765
./Scripts/location-bridge --no-xcode
./Scripts/location-bridge --no-simulator
./Scripts/location-bridge --stop
```

Xcode menu automation uses AppleScript through `osascript`. If macOS blocks it, open `System Settings > Privacy & Security > Accessibility` and allow the terminal app or process that starts the bridge. Without this permission, the bridge can still write GPX files and update simulators, but Xcode may not switch its active simulated location automatically.

If the bridge was started as a launchd job or another detached background process, pressing `Control+C` in a different terminal only stops that foreground command. Run `./Scripts/location-bridge --stop` to remove the known launchd job and stop the bridge process listening on the selected port.

## Current Location

The current-location button reads the phone's real GPS location, selects it, and centers the map. Do not run this picker app while Xcode location simulation is enabled for the picker itself. If Xcode overrides the phone's real location, the app rejects that simulated fix.

## Mainland China Coordinates

Apple Maps displays mainland China map data in GCJ-02, while Xcode GPX files expect WGS84/GPS coordinates. SimulateLocation keeps both coordinate systems internally:

- The visible red map marker uses the map display coordinate.
- The GPX sent to the Mac bridge uses the WGS84/GPS coordinate.

Outside mainland China, coordinates are not shifted.

## Limitations

iOS apps cannot directly write into a Mac project directory or change system-wide phone location by themselves. This project uses a local Mac bridge and Xcode's existing debugging workflow. Full automation depends on Xcode state, an active debug session, the GPX file being present in the Xcode project, and macOS Accessibility permission.

## License

MIT License. See [LICENSE](LICENSE).
