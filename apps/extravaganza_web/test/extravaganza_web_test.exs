defmodule ExtravaganzaWebTest do
  use ExUnit.Case, async: true

  test "exposes a placeholder shell status" do
    assert ExtravaganzaWeb.shell_status() == :placeholder
  end
end
