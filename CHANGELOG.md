# PhoenixChannelClient

## v0.3.1

* Bug fixes
  * Fix issue with socket spawning too many adaptors on reconnect timer.

## v0.3.0

* Enhancements
  * Pass `handle_info/2`, `handle_call/3`, and `haneld_cast/2` messages
    through to the channel server process  
  * Add ability to pass socket params
  * Add support for client SSL certificates
  * Use `Jason` as default JSON parser

* Bug Fixes
  * Only send heartbeat messages when the channel is connected.
  * Quiet logging output

## v0.2.0

* Bug Fixes
  * Fixed issues with missing disconnect handlers in websocket code
  * Fixed crashes when sending socket closures to channels
  * Send adapter open args to websocket
* Enhancements
  * Added reconnect timer

## v0.1.0
* Initial Release
