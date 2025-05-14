defmodule Mix.Tasks.VintageNetEthernet.Install.Docs do
  @moduledoc false

  @spec short_doc() :: String.t()
  def short_doc() do
    "Install Ethernet VintageNet Interface"
  end

  @spec example() :: String.t()
  def example() do
    ~S"""
    mix vintage_net_ethernet.install \
      --interface eth0
    """
  end

  @spec long_doc() :: String.t()
  def long_doc() do
    """
    #{short_doc()}

    ## Example

    ```sh
    #{example()}
    ```

    ## Options

    * `--interface` or `-i` - The interface name of the Ethernet device to
      install.
    """
  end
end

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.VintageNetEthernet.Install do
    @shortdoc "#{__MODULE__.Docs.short_doc()}"

    @moduledoc __MODULE__.Docs.long_doc()

    use Igniter.Mix.Task

    alias Igniter.Project.Config

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        # Groups allow for overlapping arguments for tasks by the same author
        # See the generators guide for more.
        group: :vintage_net_ethernet,
        # *other* dependencies to add
        # i.e `{:foo, "~> 2.0"}`
        adds_deps: [{:vintage_net, "~> 0.13"}],
        # *other* dependencies to add and call their associated installers, if they exist
        # i.e `{:foo, "~> 2.0"}`
        installs: [],
        # An example invocation
        example: __MODULE__.Docs.example(),
        # A list of environments that this should be installed in.
        only: nil,
        # a list of positional arguments, i.e `[:file]`
        positional: [],
        # Other tasks your task composes using `Igniter.compose_task`, passing in the CLI argv
        # This ensures your option schema includes options from nested tasks
        composes: [],
        # `OptionParser` schema
        schema: [
          interface: :string
        ],
        # Default values for the options in the `schema`
        defaults: [
          interface: "eth0"
        ],
        # CLI aliases
        aliases: [
          i: :interface
        ],
        # A list of options in the schema that are required
        required: []
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      interface = igniter.args.options[:interface]

      Config.configure(
        igniter,
        "target.exs",
        :vintage_net,
        [:config],
        {:code,
         fix_ast(
           quote do
             [{unquote(interface), %{type: VintageNetEthernet}}]
           end
         )},
        updater: fn zipper ->
          type_config =
            Sourceror.Zipper.find(
              zipper,
              &match?({{:__block__, _, [:type]}, {:__aliases__, _, [:VintageNetEthernet]}}, &1)
            )

          case type_config do
            nil ->
              Igniter.Code.List.append_to_list(
                zipper,
                fix_ast(
                  quote do
                    {unquote(interface), %{type: VintageNetEthernet}}
                  end
                )
              )

            _ ->
              {:ok, zipper}
          end
        end
      )
    end

    @spec fix_ast(ast :: Macro.t()) :: Macro.t()
    defp fix_ast(ast), do: ast |> Sourceror.to_string() |> Sourceror.parse_string!()
  end
else
  defmodule Mix.Tasks.VintageNetEthernet.Install do
    @shortdoc "#{__MODULE__.Docs.short_doc()} | Install `igniter` to use"

    @moduledoc __MODULE__.Docs.long_doc()

    use Mix.Task

    @impl Mix.Task
    def run(_argv) do
      Mix.shell().error("""
      The task 'vintage_net_ethernet.install' requires igniter. Please install igniter and try again.

      For more information, see: https://hexdocs.pm/igniter/readme.html#installation
      """)

      exit({:shutdown, 1})
    end
  end
end
