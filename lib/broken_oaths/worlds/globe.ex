defmodule BrokenOaths.Worlds.Globe do
  @moduledoc """
  Goldberg polyhedron GP(f,0) mesh: a sphere tiled with 10f²+2 tiles —
  10(f²−1) hexagons and exactly 12 pentagons.

  Built as the dual of an icosahedron subdivided at frequency f: subdivision
  vertices become tile centers; the centroids of the triangles incident to a
  vertex become that tile's corners. The icosahedron is oriented vertex-up,
  so one pentagon sits at each pole and the other ten form rings of five at
  ±26.57° latitude (the rings offset by 36° in longitude).

  There is no global (q, r) coordinate on a sphere — the 12 pentagons make
  one impossible. Topology lives entirely in each tile's `neighbors` list.

  Tile ids are deterministic for a given frequency (id 0 = north pole).
  Reference: https://en.wikipedia.org/wiki/Goldberg_polyhedron
  """

  defmodule Tile do
    @moduledoc "One tile of the globe: a hexagon, or one of the 12 pentagons."
    @enforce_keys [:id, :center, :corners, :neighbors, :pentagon?]
    defstruct [:id, :center, :corners, :neighbors, :pentagon?]

    @type t :: %__MODULE__{
            id: non_neg_integer(),
            center: {float(), float(), float()},
            corners: [{float(), float(), float()}],
            neighbors: [non_neg_integer()],
            pentagon?: boolean()
          }
  end

  @type mesh :: %{frequency: pos_integer(), tiles: %{non_neg_integer() => Tile.t()}}

  @doc "Number of tiles in a GP(f,0) globe: 10f² + 2."
  def tile_count(frequency), do: 10 * frequency * frequency + 2

  @doc """
  Get the mesh for a frequency, building and caching it on first use.
  Cached in :persistent_term (reads don't copy the ~10MB mesh per process).
  """
  def get(frequency) do
    case :persistent_term.get({__MODULE__, frequency}, nil) do
      nil ->
        mesh = build(frequency)
        :persistent_term.put({__MODULE__, frequency}, mesh)
        mesh

      mesh ->
        mesh
    end
  end

  @doc "Fetch a tile by id."
  def tile(mesh, id), do: Map.get(mesh.tiles, id)

  @doc "Latitude/longitude in degrees for a unit-sphere point."
  def latlon({x, y, z}) do
    lat = :math.asin(max(-1.0, min(1.0, z))) * 180.0 / :math.pi()
    lon = :math.atan2(y, x) * 180.0 / :math.pi()
    {lat, lon}
  end

  @doc """
  Build the GP(f,0) mesh (uncached). Deterministic: same frequency always
  produces the same tile ids and geometry.
  """
  def build(frequency) when is_integer(frequency) and frequency >= 1 do
    verts = icosa_vertices()
    faces = icosa_faces()

    {positions, face_grids} = subdivide(verts, faces, frequency)
    triangles = build_triangles(face_grids, frequency)
    centroids = triangle_centroids(triangles, positions)
    incidence = vertex_incidence(triangles)
    adjacency = vertex_adjacency(triangles)

    tiles =
      Map.new(positions, fn {id, center} ->
        angle_of = tangent_angle_fn(center)

        corners =
          incidence
          |> Map.fetch!(id)
          |> Enum.map(&Map.fetch!(centroids, &1))
          |> Enum.sort_by(angle_of)

        neighbors =
          adjacency
          |> Map.fetch!(id)
          |> MapSet.to_list()
          |> Enum.sort_by(fn n -> angle_of.(Map.fetch!(positions, n)) end)

        tile = %Tile{
          id: id,
          center: center,
          corners: corners,
          neighbors: neighbors,
          pentagon?: length(corners) == 5
        }

        {id, tile}
      end)

    %{frequency: frequency, tiles: tiles}
  end

  # -------------------------------------------------------------------
  # Icosahedron (vertex-up)
  # -------------------------------------------------------------------

  # Ring vertices sit at z = ±1/√5, horizontal radius 2/√5 → latitude atan(1/2).
  defp icosa_vertices do
    ring_z = 1.0 / :math.sqrt(5)
    ring_r = 2.0 / :math.sqrt(5)
    fifth = 2.0 * :math.pi() / 5.0

    upper =
      for k <- 0..4 do
        theta = k * fifth
        {ring_r * :math.cos(theta), ring_r * :math.sin(theta), ring_z}
      end

    lower =
      for k <- 0..4 do
        theta = k * fifth + fifth / 2.0
        {ring_r * :math.cos(theta), ring_r * :math.sin(theta), -ring_z}
      end

    # ids: 0 = north pole, 1-5 upper ring, 6-10 lower ring, 11 = south pole
    List.to_tuple([{0.0, 0.0, 1.0}] ++ upper ++ lower ++ [{0.0, 0.0, -1.0}])
  end

  # 20 faces as icosa-vertex-id triples. Fixed literal order — part of the
  # tile-id determinism contract. Upper ring U_k = 1+k, lower ring L_k = 6+k;
  # L_k sits at longitude between U_k and U_{k+1}.
  defp icosa_faces do
    north = for k <- 0..4, do: {0, 1 + k, 1 + rem(k + 1, 5)}
    band_down = for k <- 0..4, do: {1 + k, 6 + k, 1 + rem(k + 1, 5)}
    band_up = for k <- 0..4, do: {6 + k, 6 + rem(k + 1, 5), 1 + rem(k + 1, 5)}
    south = for k <- 0..4, do: {11, 6 + rem(k + 1, 5), 6 + k}
    north ++ band_down ++ band_up ++ south
  end

  # -------------------------------------------------------------------
  # Subdivision with topological dedupe
  # -------------------------------------------------------------------

  # Returns {positions :: %{id => {x,y,z}}, face_grids :: [%{{i,j} => id}]}.
  # Shared points (icosa vertices, face-edge lattice points) are deduped by
  # exact topological keys, so ids and coordinates are fully deterministic.
  defp subdivide(verts, faces, f) do
    init = {%{}, %{}, 0, []}

    {_key_to_id, positions, _next, grids_rev} =
      faces
      |> Enum.with_index()
      |> Enum.reduce(init, fn {{a, b, c}, face_idx}, acc ->
        pa = elem(verts, a)
        pb = elem(verts, b)
        pc = elem(verts, c)

        {key_to_id, positions, next_id, grids} = acc

        {key_to_id, positions, next_id, grid} =
          Enum.reduce(lattice(f), {key_to_id, positions, next_id, %{}}, fn {i, j}, acc2 ->
            {k2i, pos, nid, grid} = acc2
            key = point_key(face_idx, {a, b, c}, i, j, f)

            case Map.fetch(k2i, key) do
              {:ok, id} ->
                {k2i, pos, nid, Map.put(grid, {i, j}, id)}

              :error ->
                p = lattice_point(pa, pb, pc, i, j, f)

                {Map.put(k2i, key, nid), Map.put(pos, nid, p), nid + 1,
                 Map.put(grid, {i, j}, nid)}
            end
          end)

        {key_to_id, positions, next_id, [grid | grids]}
      end)

    {positions, Enum.reverse(grids_rev)}
  end

  defp lattice(f), do: for(i <- 0..f, j <- 0..(f - i), do: {i, j})

  # Topological identity of lattice point (i, j) on a face with corners {a, b, c}.
  # Corner → {:v, vertex}; edge → {:e, {lo, hi}, t} with t measured from the
  # lower-id vertex; interior → {:f, face, i, j} (never shared).
  defp point_key(face_idx, {a, b, c}, i, j, f) do
    cond do
      i == 0 and j == 0 -> {:v, a}
      i == f -> {:v, b}
      j == f -> {:v, c}
      j == 0 -> edge_key(a, b, i, f)
      i == 0 -> edge_key(a, c, j, f)
      i + j == f -> edge_key(b, c, j, f)
      true -> {:f, face_idx, i, j}
    end
  end

  # t is the lattice offset from vertex `from` toward vertex `to`.
  defp edge_key(from, to, t, f) do
    if from < to, do: {:e, {from, to}, t}, else: {:e, {to, from}, f - t}
  end

  defp lattice_point({ax, ay, az}, {bx, by, bz}, {cx, cy, cz}, i, j, f) do
    wa = (f - i - j) / f
    wb = i / f
    wc = j / f

    normalize(
      {wa * ax + wb * bx + wc * cx, wa * ay + wb * by + wc * cy, wa * az + wb * bz + wc * cz}
    )
  end

  # -------------------------------------------------------------------
  # Triangles, incidence, adjacency
  # -------------------------------------------------------------------

  # Each face contributes f² small triangles; none are shared between faces.
  defp build_triangles(face_grids, f) do
    Enum.flat_map(face_grids, fn grid ->
      for i <- 0..(f - 1), j <- 0..(f - 1 - i), reduce: [] do
        acc ->
          up =
            {Map.fetch!(grid, {i, j}), Map.fetch!(grid, {i + 1, j}), Map.fetch!(grid, {i, j + 1})}

          if i + j <= f - 2 do
            down =
              {Map.fetch!(grid, {i + 1, j}), Map.fetch!(grid, {i + 1, j + 1}),
               Map.fetch!(grid, {i, j + 1})}

            [down, up | acc]
          else
            [up | acc]
          end
      end
    end)
  end

  defp triangle_centroids(triangles, positions) do
    triangles
    |> Enum.with_index()
    |> Map.new(fn {{a, b, c}, idx} ->
      {ax, ay, az} = Map.fetch!(positions, a)
      {bx, by, bz} = Map.fetch!(positions, b)
      {cx, cy, cz} = Map.fetch!(positions, c)
      {idx, normalize({(ax + bx + cx) / 3.0, (ay + by + cy) / 3.0, (az + bz + cz) / 3.0})}
    end)
  end

  defp vertex_incidence(triangles) do
    triangles
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {{a, b, c}, idx}, acc ->
      acc
      |> Map.update(a, [idx], &[idx | &1])
      |> Map.update(b, [idx], &[idx | &1])
      |> Map.update(c, [idx], &[idx | &1])
    end)
  end

  defp vertex_adjacency(triangles) do
    Enum.reduce(triangles, %{}, fn {a, b, c}, acc ->
      acc
      |> add_edge(a, b)
      |> add_edge(b, c)
      |> add_edge(c, a)
    end)
  end

  defp add_edge(acc, u, v) do
    acc
    |> Map.update(u, MapSet.new([v]), &MapSet.put(&1, v))
    |> Map.update(v, MapSet.new([u]), &MapSet.put(&1, u))
  end

  # -------------------------------------------------------------------
  # Tangent-plane angle ordering
  # -------------------------------------------------------------------

  # Returns fn point -> angle of the point around `n` in n's tangent plane.
  # Ascending angle = counter-clockwise viewed from outside the sphere.
  # The reference axis falls back to +x near the poles where +z is
  # parallel to the tile normal.
  defp tangent_angle_fn({_nx, _ny, nz} = n) do
    ref = if abs(nz) > 0.9, do: {1.0, 0.0, 0.0}, else: {0.0, 0.0, 1.0}
    e1 = normalize(sub(ref, scale(n, dot(ref, n))))
    e2 = cross(n, e1)
    fn p -> :math.atan2(dot(p, e2), dot(p, e1)) end
  end

  # -------------------------------------------------------------------
  # Vector helpers
  # -------------------------------------------------------------------

  defp normalize({x, y, z}) do
    len = :math.sqrt(x * x + y * y + z * z)
    {x / len, y / len, z / len}
  end

  defp sub({ax, ay, az}, {bx, by, bz}), do: {ax - bx, ay - by, az - bz}
  defp scale({x, y, z}, s), do: {x * s, y * s, z * s}
  defp dot({ax, ay, az}, {bx, by, bz}), do: ax * bx + ay * by + az * bz

  defp cross({ax, ay, az}, {bx, by, bz}),
    do: {ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx}
end
