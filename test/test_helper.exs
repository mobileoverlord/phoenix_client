Logger.configure(level: :debug)

# Starts web server applications
Application.ensure_all_started(:cowboy)
Application.ensure_all_started(:phoenix)

Code.require_file "../deps/phoenix/test/support/router_helper.exs", __DIR__

Application.put_env(:ex_unit, :assert_receive_timeout, 500)

ExUnit.start()
