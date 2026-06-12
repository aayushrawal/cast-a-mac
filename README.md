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

### iPad client

- Discovers previously paired Macs through the coordination service.
- Decodes the hardware video stream and renders it with Metal.
- Maps Apple Pencil, touch, trackpad, and hardware keyboard input to the remote
  display coordinate space.
- Uses two-finger pans for scrolling and three-finger swipes for Mission
  Control, App Exposé, and switching Spaces.
- Offers explicit controls for display selection, bitrate, frame rate, scaling,
  clipboard sync, and disconnect.

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
- Connects to the selected Mac and decodes its H.264 stream.
- Renders the desktop with Metal.
- Reserves a separate "Your Macs" section for account-linked internet hosts.

The first local-network scan prompts for permission on iPadOS. Start
`swift run cast-host` on the Mac before opening the client.

Remote control requires Accessibility permission on the Mac. Grant it to the
Terminal or host application under System Settings > Privacy & Security >
Accessibility, then restart the host.

## Internet transport contract

`InternetSessionProvider` defines the account-facing boundary for listing Macs
and obtaining short-lived connection tickets. A production implementation
requires:

- Sign in with Apple token verification on a backend.
- Mac presence registration tied to the verified account.
- WebRTC offer/answer and ICE signaling.
- A TURN service for networks where peer-to-peer connectivity fails.
- Per-session authorization and device identity verification.

The raw LAN TCP listener is deliberately not used over the public internet. It
has no authentication or encryption and must not be port-forwarded.

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
