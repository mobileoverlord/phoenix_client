Logger.configure(level: :debug)

# Starts web server applications
Application.ensure_all_started(:cowboy)
Application.ensure_all_started(:phoenix)

Code.require_file "../deps/phoenix/test/router_helper.exs", __DIR__

ExUnit.start()
