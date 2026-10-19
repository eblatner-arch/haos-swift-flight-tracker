# Flights (iOS)

A native iPhone app for the **Flight Tracker Flighty** Home Assistant add-on
([haos-flight-tracker-flighty](https://github.com/eblatner-arch/Haos-flight-tracker-flighty)).
The add-on keeps doing all the data collection (schedule, FlightAware, AeroAPI, FAA SWIM, ADS-B);
this app reads the same API the web app uses and shows it with Apple's own map engine (MapKit),
satellite imagery and a globe when zoomed out.

Nothing in the add-on has to change for it to work.

## What's in 0.1

- My Flights: upcoming and recent, pull to refresh, refreshes every minute and when you open the app
- A flight: status and problems, both ends (time in the airport's zone, delay, gate, terminal, bags),
  the four times (scheduled / actual or estimated), the airplane (United 737 livery picture, FAA age,
  how many times you've flown the tail), the inbound aircraft and turn time
- The map: your flights' routes, or one flight's filed route, flown track and the airplane, live every 5 s;
  buttons to zoom to the route, the airplane or either airport
- Works offline: the last answers from the add-on are kept on the phone
- Opens a flight from a link: `ericsflights://leg/<id>` (for Home Assistant notifications later)

## Build and install (Mac)

1. Install Xcode (App Store) and XcodeGen: `brew install xcodegen`
2. `git clone https://github.com/eblatner-arch/haos-swift-flight-tracker && cd haos-swift-flight-tracker`
3. `xcodegen generate` then `open FlightTracker.xcodeproj`
4. Select the **FlightTracker** target → Signing & Capabilities → Team: your Apple ID / developer team
   (if the bundle ID is taken, change `com.ericsflights.flighttracker` to something of yours)
5. Plug in the iPhone (Developer Mode on: Settings → Privacy & Security), pick it as the run
   destination, press Run
6. In the app: Settings → add-on address, e.g. `https://ericsflights.duckdns.org:8090` → Test connection

With a free Apple ID the app has to be re-signed every 7 days (run it from Xcode again, or use SideStore);
with a paid developer account it lasts a year.

Every push is compiled on a Mac by GitHub Actions (Actions tab), so build errors show up there too.
