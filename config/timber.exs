use Mix.Config

# Use Timber as the logger backend
# Feel free to add additional backends if you want to send you logs to multiple devices.
# Deliver logs via HTTP to the Timber API by using the Timber HTTP backend.
config :logger,
  backends: [Timber.LoggerBackends.HTTP, :console],
  utc_log: true

config :timber,
  api_key: "1345_f1ee9b4fbd1363f8:efa544b240a3e7e1e3085a48955396f3c5066a4a5863b6aa0c9a5d03ea73cd07"

# For the following environments, do not log to the Timber service. Instead, log to STDOUT
# and format the logs properly so they are human readable.
environments_to_exclude = [:test]
if Enum.member?(environments_to_exclude, Mix.env()) do
  # Fall back to the default `:console` backend with the Timber custom formatter
  config :logger,
    backends: [:console],
    utc_log: true

  config :logger, :console,
    format: {Timber.Formatter, :format},
    metadata: [:timber_context, :event, :application, :file, :function, :line, :module, :meta]

  config :timber, Timber.Formatter,
    colorize: true,
    format: :logfmt,
    print_timestamps: true,
    print_log_level: true,
    print_metadata: false # turn this on to view the additional metadata
end

# Need help?
# Email us: support@timber.io
# Or, file an issue: https://github.com/timberio/timber-elixir/issues
