repo_root = Path.expand("../..", __DIR__)

{output, status} =
  System.cmd("mix", ["extravaganza.headless.start", "--ack-headless-guardrails", "--json"],
    cd: repo_root,
    env: [{"MIX_ENV", "test"}],
    stderr_to_stdout: true
  )

display_output = fn output ->
  max_bytes = 6_000

  if byte_size(output) > max_bytes do
    "...<truncated>...\n" <> binary_part(output, byte_size(output) - max_bytes, max_bytes)
  else
    output
  end
end

with 0 <- status,
     {:ok, %{"ok" => true, "operation" => "start"} = envelope} <- Jason.decode(output) do
  IO.puts(Jason.encode!(envelope, pretty: true))
else
  nonzero when is_integer(nonzero) ->
    IO.puts("""
    non-fixture headless start failed
    expected: MIX_ENV=test mix extravaganza.headless.start --ack-headless-guardrails --json exits 0 with an ok start envelope
    exit_status: #{nonzero}

    #{display_output.(output)}
    """)

    System.halt(1)

  {:ok, envelope} ->
    IO.puts("""
    non-fixture headless start returned an unexpected envelope
    expected: ok start envelope

    #{envelope |> Jason.encode!(pretty: true) |> display_output.()}
    """)

    System.halt(1)

  {:error, reason} ->
    IO.puts("""
    non-fixture headless start did not return JSON
    expected: ok start envelope
    decode_error: #{inspect(reason)}

    #{display_output.(output)}
    """)

    System.halt(1)
end
