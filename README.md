# Cast-a-mac

Cast-a-mac is a remote desktop system for controlling a Mac from an iPad over
the internet. It aims for the low-latency, touch-friendly feel of Sidecar while
using public Apple APIs and working when the devices are on different networks.

It is not a drop-in implementation of Sidecar. Third-party apps cannot use
Apple's private Sidecar display pipeline. The product is instead composed of a
Mac host app, an iPad client, and a small internet coordination service.

## Product shape

### Mac host

- Captures a user-selected display with ScreenCaptureKit.
- Encodes frames with VideoToolbox, preferring HEVC and falling back to H.264.
- Sends media through WebRTC.
- Receives pointer and keyboard events over a WebRTC data channel.
- Injects input with Quartz event APIs after the user grants Accessibility.
- Stores paired-device identity keys in Keychain.
- Runs as a menu bar app and can launch at login.

The Mac must be powered on, awake, connected to the internet, and running the
host app. The Mac does not need to be physically near the iPad. Remote wake is
not dependable across arbitrary internet connections, so wake-on-demand is not
an MVP promise.

The prototype host prevents idle display sleep while it is running because
ScreenCaptureKit can stop delivering frames when the physical display turns
off. A closed-lid MacBook, a headless Mac, or a Mac whose panel must remain dark
requires an attached display-emulator adapter or a future virtual-display
implementation.

### Mac menu-bar host

Build a standalone menu-bar app with:

```sh
Scripts/build-host-app.sh
```

Open `dist/Cast-a-mac Host.app`. Its display icon provides start, restart, stop,
Screen Recording settings, and Accessibility settings. The terminal
`swift run cast-host` command remains available for diagnostics.

The menu-bar app has its own macOS security identity. The first time it runs,
enable it in **Privacy & Security > Screen & System Audio Recording** and
**Privacy & Security > Accessibility**, then choose **Restart Streaming**.

### iPad client

- Discovers previously paired Macs through the coordination service.
- Decodes the hardware video stream and renders it with Metal.
- Maps Apple Pencil, touch, trackpad, and hardware keyboard input to the remote
  display coordinate space.
- Keeps a connected physical keyboard active while the software keyboard is
  hidden, including Enter, Tab, Escape, arrows, navigation keys, and common
  Command/Control/Option shortcuts.
- Uses two-finger pans for scrolling and three-finger swipes for Mission
  Control, App Exposé, and switching Spaces.
- Offers explicit controls for display selection, bitrate, frame rate, scaling,
  clipboard sync, and disconnect.

iPadOS edge gestures are deferred while the remote desktop is open, but Apple
does not let third-party apps suppress every system multitasking gesture. For a
session where all multi-finger gestures must reach the Mac, turn off the
relevant multitasking gestures in the iPad Settings app.

### Coordination service

- Authenticates devices and tracks host presence.
- Exchanges short-lived WebRTC session descriptions and ICE candidates.
- Runs TURN for networks where peer-to-peer connectivity fails.
- Never receives plaintext remote-control messages or decoded screen frames.

## Delivery phases

1. **LAN prototype:** one physical Mac display, H.264, pointer/keyboard input,
   and manual pairing.
2. **Internet MVP:** account/device presence, WebRTC signaling, TURN fallback,
   encrypted pairing, adaptive bitrate, and reconnect.
3. **Product polish:** audio, clipboard, multiple displays, Pencil gestures,
   login item, diagnostics, and App Store permission UX.
4. **Optional virtual display:** investigate a DriverKit system extension so
   the iPad can act as a separate desktop instead of mirroring a real display.
   This carries substantially more signing, entitlement, distribution, and OS
   compatibility risk than ordinary screen sharing.

## Security baseline

- Pair devices locally with a QR code or one-time code.
- Give every installation a Secure Enclave or Keychain-backed identity key.
- Require mutual device authentication before signaling a session.
- Use WebRTC DTLS-SRTP for transport encryption.
- Bind session authorization to a short-lived server token.
- Show an unmistakable host-side indicator during every active session.
- Do not expose a raw listening port on the Mac.

## Shared package

`CastCore` contains the versioned control protocol shared by the Mac and iPad
targets. It deliberately excludes media transport so the codec and WebRTC stack
can evolve without changing input and session semantics.

Run its tests with:

```sh
swift test
```

## LAN prototype

The repository now contains the first capture and media slice:

- `cast-host` discovers the first Mac display with ScreenCaptureKit.
- Screen frames are scaled to a maximum 1920-pixel long edge.
- VideoToolbox encodes the frames as real-time H.264.
- A Network.framework TCP listener broadcasts configuration and frame packets.
- `LANVideoReceiver` and `H264Decoder` provide the receiver path that the iPad
  app will use.
- The stream targets a 2732-pixel long edge at 60 fps and 18 Mbps.
- The same TCP session carries normalized pointer, click, scroll, and text
  input back to the Mac.

Build and run the host with:

```sh
swift run cast-host
```

The default TCP port is `4982`; pass another port as the first argument. The
first run prompts for Screen Recording permission. This transport is intended
only for trusted local networks: it has no authentication or encryption and
must not be exposed directly to the internet.

### iPad app

Open `CastAMac.xcodeproj`, select the `CastClient` scheme, and run it on an iPad
or iPad simulator. The client:

- Discovers running Mac hosts automatically with Bonjour.
- Lists nearby Macs without requiring an IP address.
- Gives each Mac a stable identity and remembers it after the first connection.
- Prefers the direct local connection whenever that Mac is on the same network.
- Falls back to its linked TLS WebSocket relay when the Mac is remote.
- Connects to the selected Mac and decodes its H.264 stream.
- Renders the desktop with Metal.
- Stores relay access tokens in the iPad Keychain.

The first local-network scan prompts for permission on iPadOS. Start
`swift run cast-host` on the Mac before opening the client.

Remote control requires Accessibility permission on the Mac. Grant it to the
Terminal or host application under System Settings > Privacy & Security >
Accessibility, then restart the host.

## Internet relay

`RelayServer` is a deployable Node.js WebSocket relay. Both the Mac and iPad
make outbound connections, so neither device needs a public IP address, router
configuration, or port forwarding.

Run it locally for development:

```sh
cd RelayServer
npm install
RELAY_TOKEN_SECRET="$(openssl rand -hex 32)" npm start
```

For internet use, deploy `RelayServer` behind a stable HTTPS URL. WebSocket
support must be enabled, `RELAY_TOKEN_SECRET` must remain stable across
deployments, and the service must use one instance unless the in-memory
presence maps are replaced with shared storage.

Then:

1. Enter the HTTPS relay URL in the Mac menu-bar app.
2. Choose **Save Internet Settings & Restart**.
3. Copy the Mac's eight-character link code.
4. On iPad, choose **Link a Mac** and enter the same relay URL and code.
5. Select the Mac from **Your Macs**. Local Bonjour is preferred automatically;
   the relay is used only when the local Mac ID is unavailable.

The raw LAN TCP listener remains local-only and must not be port-forwarded.
The relay uses TLS, a persistent random Mac secret, link-code pairing, and
expiring client access tokens.

### Sign in with Apple

Apple does not provide an API for reading the Apple ID currently signed into a
device. Account linking must use an explicit Sign in with Apple authorization
on both apps and backend verification of Apple's identity token. That requires
an Apple Developer App ID, Sign in with Apple entitlement, service
configuration, and production callback domain. The relay authentication
boundary is intentionally separate so Sign in with Apple can replace link
codes once those identifiers are configured.

## Next implementation slice

The next concrete slice is an Xcode workspace containing:

- `CastHost`: a sandboxed macOS menu bar app with Screen Recording and
  Accessibility permission onboarding.
- `CastClient`: an iPadOS SwiftUI app with a Metal-backed remote display view.
- `CastCore`: this package.
- `CastTransport`: initially backed by the LAN transport, then WebRTC.

Start on a local network before adding accounts or cloud signaling. That proves
capture, encode/decode, coordinate mapping, and input latency, which are the
highest-risk parts of the experience.
