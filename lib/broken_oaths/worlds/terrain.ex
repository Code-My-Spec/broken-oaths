defmodule BrokenOaths.Worlds.Terrain do
  @moduledoc """
  Civ-style terrain: a BASE type × a RELIEF form × an optional FEATURE.

    * base: :ocean | :coast | :grassland | :plains | :desert | :tundra | :snow
    * relief: :flat | :hills | :mountains (water is always flat)
    * feature: nil | :woods | :rainforest | :marsh | :ice

  Gameplay reads the components (yields from base, movement from
  relief/feature, features can be added/removed independently); rendering
  composes them into a single display color: feature overlays win, relief
  darkens hills and grays mountains.
  """

  @enforce_keys [:base]
  defstruct [:base, relief: :flat, feature: nil]

  @type t :: %__MODULE__{
          base: :ocean | :coast | :grassland | :plains | :desert | :tundra | :snow,
          relief: :flat | :hills | :mountains,
          feature: nil | :woods | :rainforest | :marsh | :ice
        }

  @base_colors %{
    ocean: "#1e3a8a",
    coast: "#3b82f6",
    grassland: "#22c55e",
    plains: "#84cc16",
    desert: "#d9c26b",
    tundra: "#8d9b8a",
    snow: "#e6ecf2"
  }

  @feature_colors %{
    woods: "#15803d",
    rainforest: "#065f46",
    marsh: "#3f6212",
    ice: "#cfe3f5"
  }

  @doc "True for water bases."
  def water?(%__MODULE__{base: base}), do: base in [:ocean, :coast]

  @doc """
  Movement points to ENTER a tile of this terrain (story 925, Civ 6's
  road/terrain movement model): DIFFICULT terrain — `:hills` relief, or
  a `:woods`/`:rainforest`/`:marsh` feature — costs 2; everything else
  costs 1. Mountains and water are never asked: they're already
  impassable at the `Regions.tile_class/2` level, one layer up from
  terrain — this only prices tiles a unit could otherwise step onto. A
  completed Road overrides this back down to 1 regardless of terrain —
  see `BrokenOaths.Units.Unit.entry_cost/3`, the caller that layers the
  road check on top of this.
  """
  @spec movement_cost(t()) :: 1 | 2
  def movement_cost(%__MODULE__{relief: :hills}), do: 2

  def movement_cost(%__MODULE__{feature: feature}) when feature in [:woods, :rainforest, :marsh],
    do: 2

  def movement_cost(%__MODULE__{}), do: 1

  @doc """
  Which billboard decor sprite (if any) this terrain earns on a canvas
  globe (ADR game-art-pipeline). Mountains dominate features; hills
  yield to tree cover. Relief is decor's job, never the texture's.
  """
  def decor(nil), do: nil
  def decor(%__MODULE__{relief: :mountains}), do: "mountain"
  def decor(%__MODULE__{feature: :woods}), do: "woods"
  def decor(%__MODULE__{feature: :rainforest}), do: "rainforest"
  def decor(%__MODULE__{relief: :hills}), do: "hills"
  def decor(%__MODULE__{}), do: nil

  @doc """
  Ground texture key for pattern fills: the feature's floor wins over
  the base's. Keys name PNGs under priv/static/images/game/terrain/.
  """
  def texture(nil), do: "ocean"
  def texture(%__MODULE__{feature: feature}) when not is_nil(feature), do: Atom.to_string(feature)
  def texture(%__MODULE__{base: base}), do: Atom.to_string(base)

  @doc """
  Display color: features overlay the base; relief still shades through
  (woods on hills render darker than woods on flats).
  """
  def color(nil), do: @base_colors.ocean

  def color(%__MODULE__{feature: feature, relief: relief}) when not is_nil(feature) do
    @feature_colors |> Map.fetch!(feature) |> relief_shade(relief)
  end

  def color(%__MODULE__{base: base, relief: relief}) do
    @base_colors |> Map.fetch!(base) |> relief_shade(relief)
  end

  @doc "Display color as {r, g, b} bytes (for the texture baker)."
  def rgb_bytes(terrain) do
    terrain |> color() |> parse_hex()
  end

  @doc ~S(Human label, e.g. "Plains Hills · Rainforest".)
  def label(nil), do: "—"

  def label(%__MODULE__{} = terrain) do
    base = terrain.base |> Atom.to_string() |> String.capitalize()

    relief =
      case terrain.relief do
        :hills -> " Hills"
        :mountains -> " Mountains"
        :flat -> ""
      end

    feature =
      case terrain.feature do
        nil -> ""
        f -> " · " <> (f |> Atom.to_string() |> String.capitalize())
      end

    base <> relief <> feature
  end

  @doc "Curated legend entries: {color, label}."
  def legend do
    [
      {color(%__MODULE__{base: :ocean}), "Ocean"},
      {color(%__MODULE__{base: :coast}), "Coast"},
      {color(%__MODULE__{base: :grassland}), "Grassland"},
      {color(%__MODULE__{base: :plains}), "Plains"},
      {color(%__MODULE__{base: :desert}), "Desert"},
      {color(%__MODULE__{base: :tundra}), "Tundra"},
      {color(%__MODULE__{base: :snow}), "Snow"},
      {color(%__MODULE__{base: :plains, relief: :hills}), "Hills"},
      {color(%__MODULE__{base: :tundra, relief: :mountains}), "Mountains"},
      {color(%__MODULE__{base: :grassland, feature: :woods}), "Woods"},
      {color(%__MODULE__{base: :plains, feature: :rainforest}), "Rainforest"},
      {color(%__MODULE__{base: :grassland, feature: :marsh}), "Marsh"},
      {color(%__MODULE__{base: :coast, feature: :ice}), "Ice"}
    ]
  end

  # -------------------------------------------------------------------
  # Color math
  # -------------------------------------------------------------------

  defp relief_shade(hex, :flat), do: hex

  defp relief_shade(hex, :hills) do
    {r, g, b} = parse_hex(hex)
    to_hex({round(r * 0.84), round(g * 0.84), round(b * 0.84)})
  end

  defp relief_shade(hex, :mountains) do
    {r, g, b} = parse_hex(hex)

    to_hex({
      round(r * 0.4 + 82 * 0.6),
      round(g * 0.4 + 82 * 0.6),
      round(b * 0.4 + 82 * 0.6)
    })
  end

  defp parse_hex("#" <> hex) do
    <<r::binary-size(2), g::binary-size(2), b::binary-size(2)>> = hex
    {String.to_integer(r, 16), String.to_integer(g, 16), String.to_integer(b, 16)}
  end

  defp to_hex({r, g, b}) do
    "#" <>
      (r |> Integer.to_string(16) |> String.pad_leading(2, "0") |> String.downcase()) <>
      (g |> Integer.to_string(16) |> String.pad_leading(2, "0") |> String.downcase()) <>
      (b |> Integer.to_string(16) |> String.pad_leading(2, "0") |> String.downcase())
  end
end
