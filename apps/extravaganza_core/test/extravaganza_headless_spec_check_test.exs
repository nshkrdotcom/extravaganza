defmodule Extravaganza.HeadlessSpecCheckTest do
  use ExUnit.Case, async: true

  alias Extravaganza.HeadlessSpecCheck

  @tag :tmp_dir
  test "detects public functions without adjacent specs", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "missing_spec.ex")

    File.write!(path, """
    defmodule Fixture.MissingSpec do
      def missing(value), do: value

      @spec covered(term()) :: term()
      def covered(value), do: value
    end
    """)

    assert [
             %{
               file: ^path,
               module: "Fixture.MissingSpec",
               name: :missing,
               arity: 1
             } = finding
           ] = HeadlessSpecCheck.missing_public_specs([path])

    assert HeadlessSpecCheck.finding_identifier(finding) == "Fixture.MissingSpec.missing/1"
  end

  @tag :tmp_dir
  test "accepts adjacent specs for default-arg public definitions and impl callbacks", %{
    tmp_dir: tmp_dir
  } do
    path = Path.join(tmp_dir, "covered_spec.ex")

    File.write!(path, """
    defmodule Fixture.CoveredSpec do
      @spec run(atom(), keyword()) :: {:ok, atom()}
      def run(kind, opts \\\\ [])
      def run(kind, _opts), do: {:ok, kind}

      @impl true
      def init(opts), do: {:ok, opts}
    end
    """)

    assert [] = HeadlessSpecCheck.missing_public_specs([path])
  end

  test "configured headless public surface has specs or documented contract tests" do
    assert [] =
             HeadlessSpecCheck.missing_public_specs(
               HeadlessSpecCheck.default_paths(),
               exemptions: HeadlessSpecCheck.default_exemptions()
             )
  end

  test "umbrella CI runs the headless public spec gate" do
    mix_path = Path.expand("../../../mix.exs", __DIR__)

    assert {:ok, mix_file} = File.read(mix_path)
    assert mix_file =~ "\"extravaganza.headless.specs.check\""
  end
end
