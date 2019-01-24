# PhoenixClient

## v0.5.0

**Important**
This version has been renamed and refactored. You will need to migrate existing
`phoenix_channel_client` projects before first use. Please see the readme for
how to implement this new pattern.

* Bug fixes
  * The Socket will monitor linked channels for down messages and remove them
    from the channel links.

* Enhancements
  * Removed the requirement to define `Socket` and `Channel` modules that implement
    their respective behaviours. Sockets are now started by calling
    `PhoenixClient.Socket.start_link` directly.
    Channels are started by calling `PhoenixClient.Channel`.
  * Calls to `PhoenixClient.Channel.push` happen synchronously. This helps to
    reduce callback spaghetti code by making the reply available at the call site.
    If you do not require a response from the server, you can use `push_async`.
  * Non-reply messages that are pushed from the server will be sent to the pid
    of the process that called join. They will be delivered as `%PhoenixClient.Message{}`.
    See the main readme for an example of this.

## v0.4.0

* Breaking changes
  * Channel pids are not longer named by default. If you would like to name the
    pid, you can pass genserver_opts to the child spec:

    For example:

    ```elixir
    {MyApp.Channel, {[socket: MyApp.Socket, topic: "room:lobby"], [name: MyApp.Channel]}}
    ```

  * Calls for `join`, `push`, `cancel_push`, and `leave` are no longer injected
    into the channel module. These functions have been moved to the
    `PhoenixClient` module.

    For example:

    ```elixir
    MyChannel.join()
    # becomes
    PhoenixClient.join(channel_pid_or_name)
    ```

## v0.3.2

* Bug fixes
  * Fix issue with rejoin timer being fired before initial join.

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
