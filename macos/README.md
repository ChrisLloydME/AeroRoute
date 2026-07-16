# AeroRoute Xcode project

Open `AeroRoute/AeroRoute.xcodeproj` with Xcode 27 and use the shared
`AeroRoute` scheme. The project keeps its Xcode 27 format and links the local
`../../AeroRouteCore` Swift Package.

The application target supports macOS, iPhone, and iPad. For a command-line
macOS Debug build from the repository root:

```bash
xcodebuild \
  -project macos/AeroRoute/AeroRoute.xcodeproj \
  -scheme AeroRoute \
  -configuration Debug \
  -destination 'platform=macOS' \
  build
```

For the unsigned generic iPhone/iPad device build, use
`-destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO`. Do not select an
iOS Simulator destination for migration verification.
