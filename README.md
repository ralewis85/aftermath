<p align="center">
  <img src=".github/images/screenshot.png" width="800" alt="Aftermath App Screenshot">
</p>

# Aftermath

A minimal 4:3 aspect ratio visionOS streaming app for Apple Vision Pro. Browse and watch live streams from the community-maintained [iptv-org](https://github.com/iptv-org/iptv) playlist.

**Note:** This app does not host or provide any video. It loads the public iptv-org playlist, which, in their words, "simply contains user-submitted links to publicly available video stream URLs." Many streams are geo-blocked or offline.

## Features

- **Stream Browser** - Search the full iptv-org index and filter by category and country
- **Favorites** - Star streams to pin them to the ornament for one-tap switching
- **Offline-Tolerant Catalog** - The last downloaded playlist is cached for when the network is unavailable
- **4:3 Aspect Ratio** - Window perfectly hugs the video content with no wasted space
- **Ornament Controls** - Volume, favorites and the stream browser float outside the video window

# Usage

## First Launch

1. Tap the **list icon** in the ornament above the video
2. Search or filter, then tap a stream to play it
3. Tap the **star** on any stream to add it to your favorites

## Controls

- **Favorite Buttons** - Switch between your starred streams
- **List Button** - Open the stream browser
- **Tap Video** - Show/hide pause/play control
- **Pause/Play Icon** - Auto-hides after 2 seconds while playing

# Building From Source

## Requirements

- Xcode 15.0 or later
- Tested on Vision OS 26.2 Beta

## Installation

1. Clone the repository:
```bash
git clone git@github.com:ralewis85/aftermath.git
cd aftermath
```

2. Open the project in Xcode:
```bash
open aftermath.xcodeproj
```

3. Select your target device (Vision Pro or Simulator)

4. Build and run (⌘R)

## Support

If you're interested in more projects like this, consider [leaving a tip](https://ko-fi.com/neovisiondev) ☕

## License

Distributed under the MIT license.

## Contributing

Contributions are welcome! Feel free to submit pull requests.

