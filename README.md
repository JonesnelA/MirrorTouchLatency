# Pure touch timing test 1.4

Unsigned iPhone/iPad test App. The default static surface records the original touchesBegan entry time for real HID touches; no per-touch drawing, animation, release wait, or video measurement is used. Read-only clock/touch telemetry listens only on device loopback port 47091 through USB mux. Network messages cannot generate touches.

The optional launch argument --touch-display-link enables continuous CADisplayLink callbacks and requests the screen maximum frame rate. It is an experiment to compare event dispatch against the static control, not a proven optimization. The callback does no drawing and cannot manufacture touch events. The formal touch timing endpoint stays unchanged. Metadata reports maximum screen FPS, observed display-link interval and timestamps, power mode and thermal state. This App-only experiment makes no claim about other applications or games.

The legacy visual test is available with --visual-test and must not be confused with pure touch timing. App 1.3 added separate UITouch/UIEvent/window dispatch timestamps; these remain diagnostic stages and never replace the touchesBegan endpoint.

GitHub Actions builds the arm64 unsigned IPA and launches the visual, static and display-link modes on an iPad simulator. Simulator checks validate the real read-only loopback protocol and active callback metadata; they do not claim real-device touch latency. Sign and install with your own valid credentials. Original bundle identifier: com.mirrortest.latency.

This public repository contains only the test App and its build/validation scripts. It contains no private mirroring source, device identifiers, user configuration, signing credentials, or real-device reports.