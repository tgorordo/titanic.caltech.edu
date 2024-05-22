### A Pluto.jl notebook ###
# v0.19.42

using Markdown
using InteractiveUtils

# ╔═╡ fc4454f6-1c07-4706-ac3f-040d9ee83994
using PlutoUI, Dates

# ╔═╡ 9a1222aa-110c-11ef-1d54-eb155df43b97
using HTTP, Gumbo, JSON, AbstractTrees, DataFrames, ReadableRegex, PrettyTables

# ╔═╡ 4741fe85-c011-451b-bef0-51cc487e978a
# ╠═╡ show_logs = false
using CondaPkg, PythonCall

# ╔═╡ e5c28754-3322-4436-9a30-ff5a95ec9ce9
using LightOSM, JuMP, GLPK, Random

# ╔═╡ 91585a4c-e842-4a87-ae02-ce9e86c3da37
using TravelingSalesmanExact, SCIP

# ╔═╡ 915bd223-4b6e-441b-a82c-05d680cc93cb
md"""
[Index](https://titanic.caltech.edu/~tgorordo)
"""

# ╔═╡ 38b70851-9587-457d-adca-50394b3f6a98
md"""
$(Resource("https://originaltommys.com/wp-content/uploads/2020/05/tommys-logo-1-min.png"))
# The Traveling Tommy's Problem
So you want to try the ultimate negative time challenge? Here's the traveling-salesman solution for all current Tommy's locations.
"""

# ╔═╡ f1344329-8d08-4d5a-bb81-13ccc50ca6ba
md"""
## Scraping the Grill
Get a list of [current locations](https://originaltommys.com/locations/).
"""

# ╔═╡ 012f104b-d3a1-4f2a-b224-86d1a711c7f4
url = "https://originaltommys.com/locations/";

# ╔═╡ acb28c38-1914-4398-84b5-1288260845bb
# Fetch the Tommy's location page and parse to scrape
rsp = HTTP.get(url); prs = parsehtml(String(rsp.body));

# ╔═╡ 8d135017-37a8-457b-ab33-e4514e223e09
# define a regex to pick out the operating hours from a table row
hoursregex = @compile look_for(one_or_more(ANY), after="Hours: ")

# ╔═╡ 021af38e-3860-4474-a901-620fc92f5d57
# and a regex to help remove the lobby hours, since that isn't relevant info
lobbyregex = @compile look_for("(Lobby " * one_or_more(ANY) * ")")

# ╔═╡ 9c316980-9940-4714-9ef9-357658a23479
df = let df = DataFrame([:Location => [], :Address => [], :Hours => []]);

	# loop over the current table of locations
	for elem in PreOrderDFS(prs.root) try if tag(elem) == :tr && 
        getattr(elem.parent.parent, "id") in ["tablepress-5", "tablepress-6"]
      
      	# extract the location name, address, and hours; push to our DataFrame
      	push!(df, [elem[1][1], elem[2][1], 
                  match(hoursregex, Gumbo.text(elem[2])).match |> 
                      string |> (s -> replace(s, lobbyregex => "")) |> strip 
      	])
    	end catch end
	end 
	transform!(df, :Address => ByRow(Gumbo.text) => :Address)
end;

# ╔═╡ bcc30610-7e29-4d70-8ae1-752681659e5f
let of = copy(df)
	pretty_table(String, of; backend=Val(:html), allow_html_in_cells=true,
		tf=PrettyTables.tf_html_minimalist, alignment=:l, 
		show_row_number=true, show_subheader=false, linebreaks=true,
		title="<code><a href='$url'>$url</a> last scraped @ $(now())</code>"
	) |> HTML
end

# ╔═╡ d31c3579-f6c1-4959-b5d8-ca38f29d119c
md"""
### Geocode
Locate addresses using [Nominatim](https://nominatim.openstreetmap.org/ui/search.html). A couple addresses need manual intervention before lookup:
"""

# ╔═╡ ada082b3-6615-45e9-818f-26e6f63f12ac
# wrong streetname
df[1,:Address]  = replace(df[1,:Address] , "Road" => "Boulevard") 

# ╔═╡ 1ac39fd7-fab9-4f22-a91b-944a69e67260
# bad city name
df[19,:Address] = replace(df[19,:Address], "North Hollywood" => "Garnsey")

# ╔═╡ c9f6c975-d9d0-4ad3-9f9a-4dacda0bb79c
# can't find address, so take the one across the street
df[22,:Address] = replace(df[22,:Address], "9301 E. Whittier Blvd" => "9298 Speedway")

# ╔═╡ 30812787-81a0-4f3d-9cd2-2df00c7c4ebd
# really just doesn't know this address
df[26,:Address] = replace(df[26,:Address], 
	"28116 N. The Old Road" => "Original Tommy's Golden State Freeway", 
	"91355" => "91310")

# ╔═╡ 4fc5b1a8-9b33-486d-950a-4647d9993aff
md"""
query the api:
"""

# ╔═╡ 47126b71-1f25-4d73-bf91-22e39a84d2cc
let api = "https://nominatim.openstreetmap.org/search?"
	places = []
	latlons = []
	for l in eachrow(df) 
		try
			res = HTTP.get(api, 
						headers=["User-Agent" => 
							"titanic.caltech.edu/1.0.0-DEV (HTTP.jl; tcgorordo@gmail.com)"],
                        query= ["q" => l[:Address], "format" => "json"]);
			@info l.Address res
    		jres = res.body |> String |> JSON.parse
			push!(places, jres[1]["place_id"])
			push!(latlons, (parse(Float64, jres[1]["lat"]), parse(Float64, jres[1]["lon"])))
			sleep(1)
  		catch e
    		@warn ("No result for " * l[:Address]) e
  		end
	end
	df[!,:placeid] = places
	df[!,:latlon] = latlons
end;

# ╔═╡ 951bfa51-da39-437c-9be2-e44648a1b868
# ╠═╡ show_logs = false
CondaPkg.add("folium"); const flm = pyimport("folium");

# ╔═╡ 715a5564-81b1-4189-84ed-c9775f438b0f
minlat, minlon = 32.363396239603740, -119.77393355557084;

# ╔═╡ 0f31dd19-bb4e-47fc-8566-645062b209c0
maxlat, maxlon = 37.178653972331674, -113.97315230557084;

# ╔═╡ 8af5b693-f17d-44b4-b49f-7786b6e9f636
boxbnd = [(minlat, minlon), (maxlat, maxlon)]

# ╔═╡ 8a55f364-495e-467f-9ca4-fa35e0318388
polybnd = [ [34.248800, -119.377205],
			[35.138756, -117.045934],
			[36.442690, -115.020941],
			[35.755994, -115.004204],
			[34.606297, -116.752006],
			[33.540679, -117.146023],
			[33.427632, -117.598244]];

# ╔═╡ 7bf4ae79-5ba5-46ae-8cfa-a198fd6b4312
let fm = flm.Map()
	flm.Polygon(polybnd, color="grey", opacity=0.8, weight=3).add_to(fm)
	flm.Rectangle(boxbnd, color="black", weight=2).add_to(fm)
	for r in eachrow(df)
		flm.Marker(r[:latlon],
			tooltip="$(rownumber(r)) $(r[:Location]): $(r[:Address])").add_to(fm)
	end
	@py fm.fit_bounds([(minlat, minlon), (maxlat, maxlon)])
	fm._repr_html_() |> HTML
end

# ╔═╡ 2f12547c-4be1-4644-85b7-c3fbdfcedf20
LightOSM.download_osm_network(
	:polygon, network_type=:drive, metadata=true, download_format=:osm,
	polygon=(collect∘map)(reverse, polybnd), # bbox = boxbnd,
	save_to_file_location="LAVegas.osm"
);

# ╔═╡ 568cc195-023c-4df3-a9fb-65f27ea534c5
md"""
[`LAVegas.osm`](https://titanic.caltech.edu/~tgorordo/LAVegas.osm)
"""

# ╔═╡ 4401458c-3535-47c6-b219-c62c101920af
g = LightOSM.graph_from_file("LAVegas.osm", network_type=:drive, weight_type=:time, largest_connected_component=true)

# ╔═╡ efcf7447-bec3-4199-a54c-d8cf1c9874ad
md"""
Route a distance matrix:
"""

# ╔═╡ 542b52d9-9f83-49d4-98e1-be2d4c5870a9
LightOSM.total_path_weight(::LightOSM.OSMGraph{U, T, W}, ::Nothing) where {U, T, W} = 0 # for a connected graph, `nothing` indicates we've asked for the path from a node to itself.

# ╔═╡ a868a31f-2cc7-4283-b0e6-27c50f43a3be
d = let nodes = map(l -> nearest_node(g, l)[1], collect.(df[!,:latlon]))
	[total_path_weight(g, shortest_path(g, a, b)) for a=nodes, b=nodes]
end

# ╔═╡ 63333464-4a87-4b14-9507-57cbcdd3d734
n = size(d, 1)

# ╔═╡ 5a635ea7-a3e7-4608-b7db-065588a0d732
function build_tsp_model(m)
	n = size(m)[1]
	model = Model(GLPK.Optimizer)
	@variable(model, x[1:n, 1:n], Bin, Symmetric)
	@objective(model, Min, sum(m .* x) / 2)
	@constraint(model, [i in 1:n], sum(x[i, [j for j in 1:n if j != i]]) == 1)
	@constraint(model, [j in 1:n], sum(x[[i for i in 1:n if i != j], j]) == 1)
	@constraint(model, [i in 1:n], x[i, i] == 0.)
	return model
end

# ╔═╡ 0bf52f3a-cacd-4310-9526-2610ef1235bb
function subtour(edges::Vector{Tuple{Int,Int}}, n)
    shortest_subtour, unvisited = collect(1:n), Set(collect(1:n))
    while !isempty(unvisited)
        this_cycle, neighbors = Int[], unvisited
        while !isempty(neighbors)
            current = pop!(neighbors)
            push!(this_cycle, current)
            if length(this_cycle) > 1
                pop!(unvisited, current)
            end
            neighbors =
                [j for (i, j) in edges if i == current && j in unvisited]
        end
        if length(this_cycle) < length(shortest_subtour)
            shortest_subtour = this_cycle
        end
    end
    return shortest_subtour
end

# ╔═╡ 39fe4d23-0e0c-4203-a026-db8fbe275815
function selected_edges(x::Matrix{Float64}, n)
    return Tuple{Int,Int}[(i, j) for i in 1:n, j in 1:n if x[i, j] > 0.5]
end

# ╔═╡ 013924bf-76ff-451b-b45b-965d020a9564
subtour(x::Matrix{Float64}) = subtour(selected_edges(x, size(x, 1)), size(x, 1))

# ╔═╡ e7b7eddc-ddde-4554-8b11-1785e381fd0e
subtour(x::AbstractMatrix{VariableRef}) = subtour(value.(x))

# ╔═╡ 26fa54e2-864c-417d-a44b-fb20550cebb2
mapsol(ps) = let fm = flm.Map()
	flm.Polygon(polybnd, color="grey", opacity=0.8, weight=3).add_to(fm)
	flm.Rectangle(boxbnd, color="black", weight=2).add_to(fm)
	#for r in eachrow(df)
	#	flm.Marker(r[:latlon]).add_to(fm)
	#end
	for p in ps
		flm.PolyLine(locations=[df[p[1], :latlon], df[p[2], :latlon]]).add_to(fm)
	end
	@py fm.fit_bounds([(minlat, minlon), (maxlat, maxlon)])
	fm._repr_html_() |> HTML
end

# ╔═╡ b136349f-c4b2-4cc8-88c2-99e2bb1688c2
begin 
	iterative_model = build_tsp_model(d)
	set_optimizer_attribute(iterative_model, "msg_lev", GLPK.GLP_MSG_ALL)
	optimize!(iterative_model)
	@assert is_solved_and_feasible(iterative_model)
	time_iterated = solve_time(iterative_model)
	cycle = subtour(iterative_model[:x])
	while 1 < length(cycle) < n
    	@info "Found cycle of length $(length(cycle))"
    	S = [(i, j) for (i, j) in Iterators.product(cycle, cycle) if i < j]
    	@constraint(
        	iterative_model,
        	sum(iterative_model[:x][i, j] for (i, j) in S) <= length(cycle) - 1,
    	)
    	optimize!(iterative_model)
    	@assert is_solved_and_feasible(iterative_model)
		a = value.(iterative_model[:x])
		p = selected_edges(a, size(a, 1))
		@info "Map:" mapsol(p)
    	global time_iterated += solve_time(iterative_model)
    	global cycle = subtour(iterative_model[:x])
	end
end

# ╔═╡ a67b7b91-3447-4874-864e-5cae0edf4d96
objective_value(iterative_model)

# ╔═╡ e10130dc-8720-4920-b13e-a3f849e238b1
sol = let a = value.(iterative_model[:x])
	s = selected_edges(a, size(a, 1))
	trail = [7] # start at eaglerock
	while length(trail) < 32
		bs = s[findall(map(p -> trail[end] in p, s))] |> Iterators.flatten |> collect |> unique |> l -> filter(x -> !in(x, trail), l)
		append!(trail, first(bs))
	end
	t = sum(total_path_weight(g, shortest_path(g, 
	nearest_node(g, collect(df[p[1], :latlon]))[1],
	nearest_node(g, collect(df[p[2], :latlon]))[1]
			)) for p in collect(zip(trail, vcat(trail[2:end], [7]))))
	rt = sum(total_path_weight(g, shortest_path(g, 
	nearest_node(g, collect(df[p[1], :latlon]))[1],
	nearest_node(g, collect(df[p[2], :latlon]))[1]
			)) for p in collect(zip(reverse(trail), vcat(reverse(trail)[2:end], [7]))))
	if rt < t
		reverse!(trail)
	end
	trail
end

# ╔═╡ e1eabfe7-ae82-4007-abb7-59681bb7bf90
let of = copy(df)[sol, :]
	pretty_table(String, of; backend=Val(:html), allow_html_in_cells=true,
		tf=PrettyTables.tf_html_minimalist, alignment=:l, 
		show_row_number=true, show_subheader=false, linebreaks=true,
		title="<code><a href='$url'>$url</a> last scraped @ $(now())</code>"
	) |> HTML
end

# ╔═╡ 35ae7286-7037-4551-ae18-557811fb9488
let fm = flm.Map()
	flm.Polygon(polybnd, color="grey", opacity=0.8, weight=3).add_to(fm)
	flm.Rectangle(boxbnd, color="black", weight=2).add_to(fm)
	for r in eachrow(df)
		flm.Marker(r[:latlon],
			tooltip="$(r[:Location]): $(r[:Address])").add_to(fm)
	end
	for p in zip(sol, vcat(sol[2:end], [7])) |> collect
		s = shortest_path(g, 
				nearest_node(g, collect(df[p[1], :latlon]))[1],
				nearest_node(g, collect(df[p[2], :latlon]))[1]
			)
		if !isnothing(s)
			ns = []
			for i in s
				l = g.nodes[i].location
				try
					push!(ns, (l.lat, l.lon))
				catch e
					@warn l e
				end
			end
			flm.PolyLine(locations=ns).add_to(fm)
		end
	end
	@py fm.fit_bounds([(minlat, minlon), (maxlat, maxlon)])
	fm._repr_html_() |> HTML
end

# ╔═╡ 00000000-0000-0000-0000-000000000001
PLUTO_PROJECT_TOML_CONTENTS = """
[deps]
AbstractTrees = "1520ce14-60c1-5f80-bbc7-55ef81b5835c"
CondaPkg = "992eb4ea-22a4-4c89-a5bb-47a3300528ab"
DataFrames = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0"
Dates = "ade2ca70-3891-5945-98fb-dc099432e06a"
GLPK = "60bf3e95-4087-53dc-ae20-288a0d20c6a6"
Gumbo = "708ec375-b3d6-5a57-a7ce-8257bf98657a"
HTTP = "cd3eb016-35fb-5094-929b-558a96fad6f3"
JSON = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
JuMP = "4076af6c-e467-56ae-b986-b466b2749572"
LightOSM = "d1922b25-af4e-4ba3-84af-fe9bea896051"
PlutoUI = "7f904dfe-b85e-4ff6-b463-dae2292396a8"
PrettyTables = "08abe8d2-0d0c-5749-adfa-8a2ac140af0d"
PythonCall = "6099a3de-0909-46bc-b1f4-468b9a2dfc0d"
Random = "9a3f8284-a2c9-5f02-9a11-845980a1fd5c"
ReadableRegex = "cbbcb084-453d-4c4c-b292-e315607ba6a4"
SCIP = "82193955-e24f-5292-bf16-6f2c5261a85f"
TravelingSalesmanExact = "737fac7d-4440-55ef-927e-002196e95561"

[compat]
AbstractTrees = "~0.4.5"
CondaPkg = "~0.2.22"
DataFrames = "~1.6.1"
GLPK = "~1.2.0"
Gumbo = "~0.8.2"
HTTP = "~1.10.6"
JSON = "~0.21.4"
JuMP = "~1.21.1"
LightOSM = "~0.3.1"
PlutoUI = "~0.7.59"
PrettyTables = "~2.3.1"
PythonCall = "~0.9.20"
ReadableRegex = "~0.3.2"
SCIP = "~0.11.14"
TravelingSalesmanExact = "~0.3.11"
"""

# ╔═╡ 00000000-0000-0000-0000-000000000002
PLUTO_MANIFEST_TOML_CONTENTS = """
# This file is machine-generated - editing it directly is not advised

julia_version = "1.10.3"
manifest_format = "2.0"
project_hash = "25430a92596131b89c522a979165c0cd9a5804b0"

[[deps.ASL_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "6252039f98492252f9e47c312c8ffda0e3b9e78d"
uuid = "ae81ac8f-d209-56e5-92de-9978fef736f9"
version = "0.1.3+0"

[[deps.AbstractPlutoDingetjes]]
deps = ["Pkg"]
git-tree-sha1 = "6e1d2a35f2f90a4bc7c2ed98079b2ba09c35b83a"
uuid = "6e696c72-6542-2067-7265-42206c756150"
version = "1.3.2"

[[deps.AbstractTrees]]
git-tree-sha1 = "2d9c9a55f9c93e8887ad391fbae72f8ef55e1177"
uuid = "1520ce14-60c1-5f80-bbc7-55ef81b5835c"
version = "0.4.5"

[[deps.ArgTools]]
uuid = "0dad84c5-d112-42e6-8d28-ef12dabb789f"
version = "1.1.1"

[[deps.ArnoldiMethod]]
deps = ["LinearAlgebra", "Random", "StaticArrays"]
git-tree-sha1 = "d57bd3762d308bded22c3b82d033bff85f6195c6"
uuid = "ec485272-7323-5ecc-a04f-4719b315124d"
version = "0.4.0"

[[deps.ArrayTools]]
git-tree-sha1 = "ca8c5218f18c5318827fdb1881f370249610f8d2"
uuid = "1dc0ca97-c5ce-4e77-ac6d-c576ac9d7f27"
version = "0.2.7"

[[deps.Artifacts]]
uuid = "56f22d72-fd6d-98f1-02f0-08ddc0907c33"

[[deps.Base64]]
uuid = "2a0f44e3-6c83-55bd-87e4-b1978d98bd5f"

[[deps.BenchmarkTools]]
deps = ["JSON", "Logging", "Printf", "Profile", "Statistics", "UUIDs"]
git-tree-sha1 = "f1dff6729bc61f4d49e140da1af55dcd1ac97b2f"
uuid = "6e4b80f9-dd63-53aa-95a3-0cdb28fa8baf"
version = "1.5.0"

[[deps.BitFlags]]
git-tree-sha1 = "2dc09997850d68179b69dafb58ae806167a32b1b"
uuid = "d1d4a3ce-64b1-5f1a-9ba4-7e7e69966f35"
version = "0.1.8"

[[deps.Bzip2_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "9e2a6b69137e6969bab0152632dcb3bc108c8bdd"
uuid = "6e34b625-4abd-537c-b88f-471c36dfa7a0"
version = "1.0.8+1"

[[deps.CEnum]]
git-tree-sha1 = "389ad5c84de1ae7cf0e28e381131c98ea87d54fc"
uuid = "fa961155-64e5-5f13-b03f-caf6b980ea82"
version = "0.5.0"

[[deps.Clustering]]
deps = ["Distances", "LinearAlgebra", "NearestNeighbors", "Printf", "Random", "SparseArrays", "Statistics", "StatsBase"]
git-tree-sha1 = "9ebb045901e9bbf58767a9f34ff89831ed711aae"
uuid = "aaaa29a8-35af-508c-8bc3-b662a17a0fe5"
version = "0.15.7"

[[deps.CodecBzip2]]
deps = ["Bzip2_jll", "Libdl", "TranscodingStreams"]
git-tree-sha1 = "9b1ca1aa6ce3f71b3d1840c538a8210a043625eb"
uuid = "523fee87-0ab8-5b00-afb7-3ecf72e48cfd"
version = "0.8.2"

[[deps.CodecZlib]]
deps = ["TranscodingStreams", "Zlib_jll"]
git-tree-sha1 = "59939d8a997469ee05c4b4944560a820f9ba0d73"
uuid = "944b1d66-785c-5afd-91f1-9de20f533193"
version = "0.7.4"

[[deps.ColorTypes]]
deps = ["FixedPointNumbers", "Random"]
git-tree-sha1 = "b10d0b65641d57b8b4d5e234446582de5047050d"
uuid = "3da002f7-5984-5a60-b8a6-cbb66c0b333f"
version = "0.11.5"

[[deps.ColorVectorSpace]]
deps = ["ColorTypes", "FixedPointNumbers", "LinearAlgebra", "SpecialFunctions", "Statistics", "TensorCore"]
git-tree-sha1 = "600cc5508d66b78aae350f7accdb58763ac18589"
uuid = "c3611d14-8923-5661-9e6a-0046d554d3a4"
version = "0.9.10"

[[deps.Colors]]
deps = ["ColorTypes", "FixedPointNumbers", "Reexport"]
git-tree-sha1 = "362a287c3aa50601b0bc359053d5c2468f0e7ce0"
uuid = "5ae59095-9a9b-59fe-a467-6f913c188581"
version = "0.12.11"

[[deps.CommonSubexpressions]]
deps = ["MacroTools", "Test"]
git-tree-sha1 = "7b8a93dba8af7e3b42fecabf646260105ac373f7"
uuid = "bbf7d656-a473-5ed7-a52c-81e309532950"
version = "0.3.0"

[[deps.Compat]]
deps = ["TOML", "UUIDs"]
git-tree-sha1 = "b1c55339b7c6c350ee89f2c1604299660525b248"
uuid = "34da2185-b29b-5c13-b0c7-acf172513d20"
version = "4.15.0"
weakdeps = ["Dates", "LinearAlgebra"]

    [deps.Compat.extensions]
    CompatLinearAlgebraExt = "LinearAlgebra"

[[deps.CompilerSupportLibraries_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "e66e0078-7015-5450-92f7-15fbd957f2ae"
version = "1.1.1+0"

[[deps.ConcurrentUtilities]]
deps = ["Serialization", "Sockets"]
git-tree-sha1 = "6cbbd4d241d7e6579ab354737f4dd95ca43946e1"
uuid = "f0e56b4a-5159-44fe-b623-3e5288b988bb"
version = "2.4.1"

[[deps.CondaPkg]]
deps = ["JSON3", "Markdown", "MicroMamba", "Pidfile", "Pkg", "Preferences", "TOML"]
git-tree-sha1 = "e81c4263c7ef4eca4d645ef612814d72e9255b41"
uuid = "992eb4ea-22a4-4c89-a5bb-47a3300528ab"
version = "0.2.22"

[[deps.ConstructionBase]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "260fd2400ed2dab602a7c15cf10c1933c59930a2"
uuid = "187b0558-2788-49d3-abe0-74a17ed4e7c9"
version = "1.5.5"

    [deps.ConstructionBase.extensions]
    ConstructionBaseIntervalSetsExt = "IntervalSets"
    ConstructionBaseStaticArraysExt = "StaticArrays"

    [deps.ConstructionBase.weakdeps]
    IntervalSets = "8197267c-284f-5f27-9208-e0e47529a953"
    StaticArrays = "90137ffa-7385-5640-81b9-e52037218182"

[[deps.Contour]]
deps = ["StaticArrays"]
git-tree-sha1 = "9f02045d934dc030edad45944ea80dbd1f0ebea7"
uuid = "d38c429a-6771-53c6-b99e-75d170b6e991"
version = "0.5.7"

[[deps.Crayons]]
git-tree-sha1 = "249fe38abf76d48563e2f4556bebd215aa317e15"
uuid = "a8cc5b0e-0ffa-5ad4-8c14-923d3ee1735f"
version = "4.1.1"

[[deps.DataAPI]]
git-tree-sha1 = "abe83f3a2f1b857aac70ef8b269080af17764bbe"
uuid = "9a962f9c-6df0-11e9-0e5d-c546b8b5ee8a"
version = "1.16.0"

[[deps.DataFrames]]
deps = ["Compat", "DataAPI", "DataStructures", "Future", "InlineStrings", "InvertedIndices", "IteratorInterfaceExtensions", "LinearAlgebra", "Markdown", "Missings", "PooledArrays", "PrecompileTools", "PrettyTables", "Printf", "REPL", "Random", "Reexport", "SentinelArrays", "SortingAlgorithms", "Statistics", "TableTraits", "Tables", "Unicode"]
git-tree-sha1 = "04c738083f29f86e62c8afc341f0967d8717bdb8"
uuid = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0"
version = "1.6.1"

[[deps.DataStructures]]
deps = ["Compat", "InteractiveUtils", "OrderedCollections"]
git-tree-sha1 = "1d0a14036acb104d9e89698bd408f63ab58cdc82"
uuid = "864edb3b-99cc-5e75-8d2d-829cb0a9cfe8"
version = "0.18.20"

[[deps.DataValueInterfaces]]
git-tree-sha1 = "bfc1187b79289637fa0ef6d4436ebdfe6905cbd6"
uuid = "e2d170a0-9d28-54be-80f0-106bbe20a464"
version = "1.0.0"

[[deps.Dates]]
deps = ["Printf"]
uuid = "ade2ca70-3891-5945-98fb-dc099432e06a"

[[deps.DiffResults]]
deps = ["StaticArraysCore"]
git-tree-sha1 = "782dd5f4561f5d267313f23853baaaa4c52ea621"
uuid = "163ba53b-c6d8-5494-b064-1a9d43ac40c5"
version = "1.1.0"

[[deps.DiffRules]]
deps = ["IrrationalConstants", "LogExpFunctions", "NaNMath", "Random", "SpecialFunctions"]
git-tree-sha1 = "23163d55f885173722d1e4cf0f6110cdbaf7e272"
uuid = "b552c78f-8df3-52c6-915a-8e097449b14b"
version = "1.15.1"

[[deps.Distances]]
deps = ["LinearAlgebra", "Statistics", "StatsAPI"]
git-tree-sha1 = "66c4c81f259586e8f002eacebc177e1fb06363b0"
uuid = "b4f34e82-e78d-54a5-968a-f98e89d6e8f7"
version = "0.10.11"

    [deps.Distances.extensions]
    DistancesChainRulesCoreExt = "ChainRulesCore"
    DistancesSparseArraysExt = "SparseArrays"

    [deps.Distances.weakdeps]
    ChainRulesCore = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"
    SparseArrays = "2f01184e-e22b-5df5-ae63-d93ebab69eaf"

[[deps.Distributed]]
deps = ["Random", "Serialization", "Sockets"]
uuid = "8ba89e20-285c-5b6f-9357-94700520ee1b"

[[deps.DocStringExtensions]]
deps = ["LibGit2"]
git-tree-sha1 = "2fb1e02f2b635d0845df5d7c167fec4dd739b00d"
uuid = "ffbed154-4ef7-542d-bbb7-c09d3a79fcae"
version = "0.9.3"

[[deps.Downloads]]
deps = ["ArgTools", "FileWatching", "LibCURL", "NetworkOptions"]
uuid = "f43a241f-c20a-4ad4-852c-f6b1247861c6"
version = "1.6.0"

[[deps.EarCut_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "e3290f2d49e661fbd94046d7e3726ffcb2d41053"
uuid = "5ae413db-bbd1-5e63-b57d-d24a61df00f5"
version = "2.2.4+0"

[[deps.ExceptionUnwrapping]]
deps = ["Test"]
git-tree-sha1 = "dcb08a0d93ec0b1cdc4af184b26b591e9695423a"
uuid = "460bff9d-24e4-43bc-9d9f-a8973cb893f4"
version = "0.1.10"

[[deps.Extents]]
git-tree-sha1 = "2140cd04483da90b2da7f99b2add0750504fc39c"
uuid = "411431e0-e8b7-467b-b5e0-f676ba4f2910"
version = "0.1.2"

[[deps.FileIO]]
deps = ["Pkg", "Requires", "UUIDs"]
git-tree-sha1 = "82d8afa92ecf4b52d78d869f038ebfb881267322"
uuid = "5789e2e9-d7fb-5bc7-8068-2c6fae9b9549"
version = "1.16.3"

[[deps.FileWatching]]
uuid = "7b1f6079-737a-58dc-b8bc-7a2ca5c1b5ee"

[[deps.FixedPointNumbers]]
deps = ["Statistics"]
git-tree-sha1 = "335bfdceacc84c5cdf16aadc768aa5ddfc5383cc"
uuid = "53c48c17-4a7d-5ca2-90c5-79b7896eea93"
version = "0.8.4"

[[deps.ForwardDiff]]
deps = ["CommonSubexpressions", "DiffResults", "DiffRules", "LinearAlgebra", "LogExpFunctions", "NaNMath", "Preferences", "Printf", "Random", "SpecialFunctions"]
git-tree-sha1 = "cf0fe81336da9fb90944683b8c41984b08793dad"
uuid = "f6369f11-7733-5829-9624-2563aa707210"
version = "0.10.36"
weakdeps = ["StaticArrays"]

    [deps.ForwardDiff.extensions]
    ForwardDiffStaticArraysExt = "StaticArrays"

[[deps.FreeType]]
deps = ["CEnum", "FreeType2_jll"]
git-tree-sha1 = "907369da0f8e80728ab49c1c7e09327bf0d6d999"
uuid = "b38be410-82b0-50bf-ab77-7b57e271db43"
version = "4.1.1"

[[deps.FreeType2_jll]]
deps = ["Artifacts", "Bzip2_jll", "JLLWrappers", "Libdl", "Zlib_jll"]
git-tree-sha1 = "d8db6a5a2fe1381c1ea4ef2cab7c69c2de7f9ea0"
uuid = "d7e528f0-a631-5988-bf34-fe36492bcfd7"
version = "2.13.1+0"

[[deps.FreeTypeAbstraction]]
deps = ["ColorVectorSpace", "Colors", "FreeType", "GeometryBasics"]
git-tree-sha1 = "b5c7fe9cea653443736d264b85466bad8c574f4a"
uuid = "663a7486-cb36-511b-a19d-713bb74d65c9"
version = "0.9.9"

[[deps.Future]]
deps = ["Random"]
uuid = "9fa8497b-333b-5362-9e8d-4d0656e87820"

[[deps.GLPK]]
deps = ["GLPK_jll", "MathOptInterface"]
git-tree-sha1 = "3ea2b8751474084c3c7a344a15ed725fb805dd2b"
uuid = "60bf3e95-4087-53dc-ae20-288a0d20c6a6"
version = "1.2.0"

[[deps.GLPK_jll]]
deps = ["Artifacts", "GMP_jll", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "fe68622f32828aa92275895fdb324a85894a5b1b"
uuid = "e8aa6df9-e6ca-548a-97ff-1f85fc5b8b98"
version = "5.0.1+0"

[[deps.GMP_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "781609d7-10c4-51f6-84f2-b8444358ff6d"
version = "6.2.1+6"

[[deps.GeoInterface]]
deps = ["Extents"]
git-tree-sha1 = "801aef8228f7f04972e596b09d4dba481807c913"
uuid = "cf35fbd7-0cd7-5166-be24-54bfbe79505f"
version = "1.3.4"

[[deps.GeometryBasics]]
deps = ["EarCut_jll", "Extents", "GeoInterface", "IterTools", "LinearAlgebra", "StaticArrays", "StructArrays", "Tables"]
git-tree-sha1 = "b62f2b2d76cee0d61a2ef2b3118cd2a3215d3134"
uuid = "5c1252a2-5f33-56bf-86c9-59e7332b4326"
version = "0.4.11"

[[deps.Graphs]]
deps = ["ArnoldiMethod", "Compat", "DataStructures", "Distributed", "Inflate", "LinearAlgebra", "Random", "SharedArrays", "SimpleTraits", "SparseArrays", "Statistics"]
git-tree-sha1 = "4f2b57488ac7ee16124396de4f2bbdd51b2602ad"
uuid = "86223c79-3864-5bf0-83f7-82e725a168b6"
version = "1.11.0"

[[deps.Gumbo]]
deps = ["AbstractTrees", "Gumbo_jll", "Libdl"]
git-tree-sha1 = "a1a138dfbf9df5bace489c7a9d5196d6afdfa140"
uuid = "708ec375-b3d6-5a57-a7ce-8257bf98657a"
version = "0.8.2"

[[deps.Gumbo_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "29070dee9df18d9565276d68a596854b1764aa38"
uuid = "528830af-5a63-567c-a44a-034ed33b8444"
version = "0.10.2+0"

[[deps.HTTP]]
deps = ["Base64", "CodecZlib", "ConcurrentUtilities", "Dates", "ExceptionUnwrapping", "Logging", "LoggingExtras", "MbedTLS", "NetworkOptions", "OpenSSL", "Random", "SimpleBufferStream", "Sockets", "URIs", "UUIDs"]
git-tree-sha1 = "2c3ec1f90bb4a8f7beafb0cffea8a4c3f4e636ab"
uuid = "cd3eb016-35fb-5094-929b-558a96fad6f3"
version = "1.10.6"

[[deps.Hwloc_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "ca0f6bf568b4bfc807e7537f081c81e35ceca114"
uuid = "e33a78d0-f292-5ffc-b300-72abe9b543c8"
version = "2.10.0+0"

[[deps.Hyperscript]]
deps = ["Test"]
git-tree-sha1 = "179267cfa5e712760cd43dcae385d7ea90cc25a4"
uuid = "47d2ed2b-36de-50cf-bf87-49c2cf4b8b91"
version = "0.0.5"

[[deps.HypertextLiteral]]
deps = ["Tricks"]
git-tree-sha1 = "7134810b1afce04bbc1045ca1985fbe81ce17653"
uuid = "ac1192a8-f4b3-4bfe-ba22-af5b92cd3ab2"
version = "0.9.5"

[[deps.IOCapture]]
deps = ["Logging", "Random"]
git-tree-sha1 = "8b72179abc660bfab5e28472e019392b97d0985c"
uuid = "b5f81e59-6552-4d32-b1f0-c071b021bf89"
version = "0.2.4"

[[deps.Inflate]]
git-tree-sha1 = "ea8031dea4aff6bd41f1df8f2fdfb25b33626381"
uuid = "d25df0c9-e2be-5dd7-82c8-3ad0b3e990b9"
version = "0.1.4"

[[deps.InlineStrings]]
deps = ["Parsers"]
git-tree-sha1 = "9cc2baf75c6d09f9da536ddf58eb2f29dedaf461"
uuid = "842dd82b-1e85-43dc-bf29-5d0ee9dffc48"
version = "1.4.0"

[[deps.InteractiveUtils]]
deps = ["Markdown"]
uuid = "b77e0a4c-d291-57a0-90e8-8db25a27a240"

[[deps.InvertedIndices]]
git-tree-sha1 = "0dc7b50b8d436461be01300fd8cd45aa0274b038"
uuid = "41ab1584-1d38-5bbf-9106-f11c6c58b48f"
version = "1.3.0"

[[deps.Ipopt_jll]]
deps = ["ASL_jll", "Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "MUMPS_seq_jll", "SPRAL_jll", "libblastrampoline_jll"]
git-tree-sha1 = "f06a7fd68e29c8acc96483d6f163dab58626c4b5"
uuid = "9cc047cb-c261-5740-88fc-0cf96f7bdcc7"
version = "300.1400.1302+0"

[[deps.IrrationalConstants]]
git-tree-sha1 = "630b497eafcc20001bba38a4651b327dcfc491d2"
uuid = "92d709cd-6900-40b7-9082-c6be49f344b6"
version = "0.2.2"

[[deps.IterTools]]
git-tree-sha1 = "42d5f897009e7ff2cf88db414a389e5ed1bdd023"
uuid = "c8e1da08-722c-5040-9ed9-7db0dc04731e"
version = "1.10.0"

[[deps.IteratorInterfaceExtensions]]
git-tree-sha1 = "a3f24677c21f5bbe9d2a714f95dcd58337fb2856"
uuid = "82899510-4779-5014-852e-03e436cf321d"
version = "1.0.0"

[[deps.JLD2]]
deps = ["FileIO", "MacroTools", "Mmap", "OrderedCollections", "Pkg", "PrecompileTools", "Printf", "Reexport", "Requires", "TranscodingStreams", "UUIDs"]
git-tree-sha1 = "5ea6acdd53a51d897672edb694e3cc2912f3f8a7"
uuid = "033835bb-8acc-5ee8-8aae-3f567f8a3819"
version = "0.4.46"

[[deps.JLLWrappers]]
deps = ["Artifacts", "Preferences"]
git-tree-sha1 = "7e5d6779a1e09a36db2a7b6cff50942a0a7d0fca"
uuid = "692b3bcd-3c85-4b1f-b108-f13ce0eb3210"
version = "1.5.0"

[[deps.JSON]]
deps = ["Dates", "Mmap", "Parsers", "Unicode"]
git-tree-sha1 = "31e996f0a15c7b280ba9f76636b3ff9e2ae58c9a"
uuid = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
version = "0.21.4"

[[deps.JSON3]]
deps = ["Dates", "Mmap", "Parsers", "PrecompileTools", "StructTypes", "UUIDs"]
git-tree-sha1 = "eb3edce0ed4fa32f75a0a11217433c31d56bd48b"
uuid = "0f8b85d8-7281-11e9-16c2-39a750bddbf1"
version = "1.14.0"

    [deps.JSON3.extensions]
    JSON3ArrowExt = ["ArrowTypes"]

    [deps.JSON3.weakdeps]
    ArrowTypes = "31f734f8-188a-4ce0-8406-c8a06bd891cd"

[[deps.JuMP]]
deps = ["LinearAlgebra", "MacroTools", "MathOptInterface", "MutableArithmetics", "OrderedCollections", "PrecompileTools", "Printf", "SparseArrays"]
git-tree-sha1 = "07385c772da34d91fc55d6c704b6224302082ba0"
uuid = "4076af6c-e467-56ae-b986-b466b2749572"
version = "1.21.1"

    [deps.JuMP.extensions]
    JuMPDimensionalDataExt = "DimensionalData"

    [deps.JuMP.weakdeps]
    DimensionalData = "0703355e-b756-11e9-17c0-8b28908087d0"

[[deps.LaTeXStrings]]
git-tree-sha1 = "50901ebc375ed41dbf8058da26f9de442febbbec"
uuid = "b964fa9f-0449-5b57-a5c2-d3ea65f4040f"
version = "1.3.1"

[[deps.LazyArtifacts]]
deps = ["Artifacts", "Pkg"]
uuid = "4af54fe1-eca0-43a8-85a7-787d91b784e3"

[[deps.LazyModules]]
git-tree-sha1 = "a560dd966b386ac9ae60bdd3a3d3a326062d3c3e"
uuid = "8cdb02fc-e678-4876-92c5-9defec4f444e"
version = "0.3.1"

[[deps.LibCURL]]
deps = ["LibCURL_jll", "MozillaCACerts_jll"]
uuid = "b27032c2-a3e7-50c8-80cd-2d36dbcbfd21"
version = "0.6.4"

[[deps.LibCURL_jll]]
deps = ["Artifacts", "LibSSH2_jll", "Libdl", "MbedTLS_jll", "Zlib_jll", "nghttp2_jll"]
uuid = "deac9b47-8bc7-5906-a0fe-35ac56dc84c0"
version = "8.4.0+0"

[[deps.LibGit2]]
deps = ["Base64", "LibGit2_jll", "NetworkOptions", "Printf", "SHA"]
uuid = "76f85450-5226-5b5a-8eaa-529ad045b433"

[[deps.LibGit2_jll]]
deps = ["Artifacts", "LibSSH2_jll", "Libdl", "MbedTLS_jll"]
uuid = "e37daf67-58a4-590a-8e99-b0245dd2ffc5"
version = "1.6.4+0"

[[deps.LibSSH2_jll]]
deps = ["Artifacts", "Libdl", "MbedTLS_jll"]
uuid = "29816b5a-b9ab-546f-933c-edad1886dfa8"
version = "1.11.0+1"

[[deps.Libdl]]
uuid = "8f399da3-3557-5675-b5ff-fb832c97cbdb"

[[deps.Libiconv_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "f9557a255370125b405568f9767d6d195822a175"
uuid = "94ce4f54-9a6c-5748-9c1c-f9c7231a4531"
version = "1.17.0+0"

[[deps.LightOSM]]
deps = ["DataStructures", "Graphs", "HTTP", "JSON", "LightXML", "MetaGraphs", "NearestNeighbors", "Parameters", "QuickHeaps", "SimpleWeightedGraphs", "SparseArrays", "SpatialIndexing", "StaticArrays", "StaticGraphs", "Statistics"]
git-tree-sha1 = "e51da5bd942c69b917a2b8d2204f61a8aab95821"
uuid = "d1922b25-af4e-4ba3-84af-fe9bea896051"
version = "0.3.1"

[[deps.LightXML]]
deps = ["Libdl", "XML2_jll"]
git-tree-sha1 = "3a994404d3f6709610701c7dabfc03fed87a81f8"
uuid = "9c8b4983-aa76-5018-a973-4c85ecc9e179"
version = "0.9.1"

[[deps.LinearAlgebra]]
deps = ["Libdl", "OpenBLAS_jll", "libblastrampoline_jll"]
uuid = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"

[[deps.LogExpFunctions]]
deps = ["DocStringExtensions", "IrrationalConstants", "LinearAlgebra"]
git-tree-sha1 = "18144f3e9cbe9b15b070288eef858f71b291ce37"
uuid = "2ab3a3ac-af41-5b50-aa03-7779005ae688"
version = "0.3.27"

    [deps.LogExpFunctions.extensions]
    LogExpFunctionsChainRulesCoreExt = "ChainRulesCore"
    LogExpFunctionsChangesOfVariablesExt = "ChangesOfVariables"
    LogExpFunctionsInverseFunctionsExt = "InverseFunctions"

    [deps.LogExpFunctions.weakdeps]
    ChainRulesCore = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"
    ChangesOfVariables = "9e997f8a-9a97-42d5-a9f1-ce6bfc15e2c0"
    InverseFunctions = "3587e190-3f89-42d0-90ee-14403ec27112"

[[deps.Logging]]
uuid = "56ddb016-857b-54e1-b83d-db4d58db5568"

[[deps.LoggingExtras]]
deps = ["Dates", "Logging"]
git-tree-sha1 = "c1dd6d7978c12545b4179fb6153b9250c96b0075"
uuid = "e6f89c97-d47a-5376-807f-9c37f3926c36"
version = "1.0.3"

[[deps.METIS_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "1fd0a97409e418b78c53fac671cf4622efdf0f21"
uuid = "d00139f3-1899-568f-a2f0-47f597d42d70"
version = "5.1.2+0"

[[deps.MIMEs]]
git-tree-sha1 = "65f28ad4b594aebe22157d6fac869786a255b7eb"
uuid = "6c6e2e6c-3030-632d-7369-2d6c69616d65"
version = "0.1.4"

[[deps.MUMPS_seq_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "METIS_jll", "libblastrampoline_jll"]
git-tree-sha1 = "24dd34802044008ef9a596de32d63f3c9ddb7802"
uuid = "d7ed1dd3-d0ae-5e8e-bfb4-87a502085b8d"
version = "500.600.100+0"

[[deps.MacroTools]]
deps = ["Markdown", "Random"]
git-tree-sha1 = "2fa9ee3e63fd3a4f7a9a4f4744a52f4856de82df"
uuid = "1914dd2f-81c6-5fcd-8719-6d5c9610ff09"
version = "0.5.13"

[[deps.MarchingCubes]]
deps = ["PrecompileTools", "StaticArrays"]
git-tree-sha1 = "27d162f37cc29de047b527dab11a826dd3a650ad"
uuid = "299715c1-40a9-479a-aaf9-4a633d36f717"
version = "0.1.9"

[[deps.Markdown]]
deps = ["Base64"]
uuid = "d6f4376e-aef5-505a-96c1-9c027394607a"

[[deps.MathOptInterface]]
deps = ["BenchmarkTools", "CodecBzip2", "CodecZlib", "DataStructures", "ForwardDiff", "JSON", "LinearAlgebra", "MutableArithmetics", "NaNMath", "OrderedCollections", "PrecompileTools", "Printf", "SparseArrays", "SpecialFunctions", "Test", "Unicode"]
git-tree-sha1 = "9cc5acd6b76174da7503d1de3a6f8cf639b6e5cb"
uuid = "b8f27783-ece8-5eb3-8dc8-9495eed66fee"
version = "1.29.0"

[[deps.MbedTLS]]
deps = ["Dates", "MbedTLS_jll", "MozillaCACerts_jll", "NetworkOptions", "Random", "Sockets"]
git-tree-sha1 = "c067a280ddc25f196b5e7df3877c6b226d390aaf"
uuid = "739be429-bea8-5141-9913-cc70e7f3736d"
version = "1.1.9"

[[deps.MbedTLS_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "c8ffd9c3-330d-5841-b78e-0817d7145fa1"
version = "2.28.2+1"

[[deps.MetaGraphs]]
deps = ["Graphs", "JLD2", "Random"]
git-tree-sha1 = "1130dbe1d5276cb656f6e1094ce97466ed700e5a"
uuid = "626554b9-1ddb-594c-aa3c-2596fe9399a5"
version = "0.7.2"

[[deps.MicroMamba]]
deps = ["Pkg", "Scratch", "micromamba_jll"]
git-tree-sha1 = "011cab361eae7bcd7d278f0a7a00ff9c69000c51"
uuid = "0b3b1443-0f03-428d-bdfb-f27f9c1191ea"
version = "0.1.14"

[[deps.Missings]]
deps = ["DataAPI"]
git-tree-sha1 = "ec4f7fbeab05d7747bdf98eb74d130a2a2ed298d"
uuid = "e1d29d7a-bbdc-5cf2-9ac0-f12de2c33e28"
version = "1.2.0"

[[deps.Mmap]]
uuid = "a63ad114-7e13-5084-954f-fe012c677804"

[[deps.MozillaCACerts_jll]]
uuid = "14a3606d-f60d-562e-9121-12d972cd8159"
version = "2023.1.10"

[[deps.MutableArithmetics]]
deps = ["LinearAlgebra", "SparseArrays", "Test"]
git-tree-sha1 = "a3589efe0005fc4718775d8641b2de9060d23f73"
uuid = "d8a4904e-b15c-11e9-3269-09a3773c0cb0"
version = "1.4.4"

[[deps.NaNMath]]
deps = ["OpenLibm_jll"]
git-tree-sha1 = "0877504529a3e5c3343c6f8b4c0381e57e4387e4"
uuid = "77ba4419-2d1f-58cd-9bb1-8ffee604a2e3"
version = "1.0.2"

[[deps.Ncurses_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "3ac1ca10bae513c9cc8f83d7734b921b8007b574"
uuid = "68e3532b-a499-55ff-9963-d1c0c0748b3a"
version = "6.5.0+0"

[[deps.NearestNeighbors]]
deps = ["Distances", "StaticArrays"]
git-tree-sha1 = "ded64ff6d4fdd1cb68dfcbb818c69e144a5b2e4c"
uuid = "b8a86587-4115-5ab1-83bc-aa920d37bbce"
version = "0.4.16"

[[deps.NetworkOptions]]
uuid = "ca575930-c2e3-43a9-ace4-1e988b2c1908"
version = "1.2.0"

[[deps.OpenBLAS32_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl"]
git-tree-sha1 = "6065c4cff8fee6c6770b277af45d5082baacdba1"
uuid = "656ef2d0-ae68-5445-9ca0-591084a874a2"
version = "0.3.24+0"

[[deps.OpenBLAS_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "Libdl"]
uuid = "4536629a-c528-5b80-bd46-f80d51c5b363"
version = "0.3.23+4"

[[deps.OpenLibm_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "05823500-19ac-5b8b-9628-191a04bc5112"
version = "0.8.1+2"

[[deps.OpenSSL]]
deps = ["BitFlags", "Dates", "MozillaCACerts_jll", "OpenSSL_jll", "Sockets"]
git-tree-sha1 = "38cb508d080d21dc1128f7fb04f20387ed4c0af4"
uuid = "4d8831e6-92b7-49fb-bdf8-b643e874388c"
version = "1.4.3"

[[deps.OpenSSL_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "3da7367955dcc5c54c1ba4d402ccdc09a1a3e046"
uuid = "458c3c95-2e84-50aa-8efc-19380b2a3a95"
version = "3.0.13+1"

[[deps.OpenSpecFun_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "13652491f6856acfd2db29360e1bbcd4565d04f1"
uuid = "efe28fd5-8261-553b-a9e1-b2916fc3738e"
version = "0.5.5+0"

[[deps.OrderedCollections]]
git-tree-sha1 = "dfdf5519f235516220579f949664f1bf44e741c5"
uuid = "bac558e1-5e72-5ebc-8fee-abe8a469f55d"
version = "1.6.3"

[[deps.Parameters]]
deps = ["OrderedCollections", "UnPack"]
git-tree-sha1 = "34c0e9ad262e5f7fc75b10a9952ca7692cfc5fbe"
uuid = "d96e819e-fc66-5662-9728-84c9c7592b0a"
version = "0.12.3"

[[deps.Parsers]]
deps = ["Dates", "PrecompileTools", "UUIDs"]
git-tree-sha1 = "8489905bcdbcfac64d1daa51ca07c0d8f0283821"
uuid = "69de0a69-1ddd-5017-9359-2bf0b02dc9f0"
version = "2.8.1"

[[deps.Pidfile]]
deps = ["FileWatching", "Test"]
git-tree-sha1 = "2d8aaf8ee10df53d0dfb9b8ee44ae7c04ced2b03"
uuid = "fa939f87-e72e-5be4-a000-7fc836dbe307"
version = "1.3.0"

[[deps.Pkg]]
deps = ["Artifacts", "Dates", "Downloads", "FileWatching", "LibGit2", "Libdl", "Logging", "Markdown", "Printf", "REPL", "Random", "SHA", "Serialization", "TOML", "Tar", "UUIDs", "p7zip_jll"]
uuid = "44cfe95a-1eb2-52ea-b672-e2afdf69b78f"
version = "1.10.0"

[[deps.PlutoUI]]
deps = ["AbstractPlutoDingetjes", "Base64", "ColorTypes", "Dates", "FixedPointNumbers", "Hyperscript", "HypertextLiteral", "IOCapture", "InteractiveUtils", "JSON", "Logging", "MIMEs", "Markdown", "Random", "Reexport", "URIs", "UUIDs"]
git-tree-sha1 = "ab55ee1510ad2af0ff674dbcced5e94921f867a9"
uuid = "7f904dfe-b85e-4ff6-b463-dae2292396a8"
version = "0.7.59"

[[deps.PooledArrays]]
deps = ["DataAPI", "Future"]
git-tree-sha1 = "36d8b4b899628fb92c2749eb488d884a926614d3"
uuid = "2dfb63ee-cc39-5dd5-95bd-886bf059d720"
version = "1.4.3"

[[deps.PrecompileTools]]
deps = ["Preferences"]
git-tree-sha1 = "5aa36f7049a63a1528fe8f7c3f2113413ffd4e1f"
uuid = "aea7be01-6a6a-4083-8856-8a6e6704d82a"
version = "1.2.1"

[[deps.Preferences]]
deps = ["TOML"]
git-tree-sha1 = "9306f6085165d270f7e3db02af26a400d580f5c6"
uuid = "21216c6a-2e73-6563-6e65-726566657250"
version = "1.4.3"

[[deps.PrettyTables]]
deps = ["Crayons", "LaTeXStrings", "Markdown", "PrecompileTools", "Printf", "Reexport", "StringManipulation", "Tables"]
git-tree-sha1 = "88b895d13d53b5577fd53379d913b9ab9ac82660"
uuid = "08abe8d2-0d0c-5749-adfa-8a2ac140af0d"
version = "2.3.1"

[[deps.Printf]]
deps = ["Unicode"]
uuid = "de0858da-6303-5e67-8744-51eddeeeb8d7"

[[deps.Profile]]
deps = ["Printf"]
uuid = "9abbd945-dff8-562f-b5e8-e1ebf5ef1b79"

[[deps.PythonCall]]
deps = ["CondaPkg", "Dates", "Libdl", "MacroTools", "Markdown", "Pkg", "REPL", "Requires", "Serialization", "Tables", "UnsafePointers"]
git-tree-sha1 = "8de9e6cbabc9bcad4f325bd9f2f1e83361e5037d"
uuid = "6099a3de-0909-46bc-b1f4-468b9a2dfc0d"
version = "0.9.20"

[[deps.QuickHeaps]]
deps = ["ArrayTools", "DataStructures"]
git-tree-sha1 = "ff720a9c8356004cc9e3d109cdcb327510345edc"
uuid = "30b38841-0f52-47f8-a5f8-18d5d4064379"
version = "0.1.2"

[[deps.REPL]]
deps = ["InteractiveUtils", "Markdown", "Sockets", "Unicode"]
uuid = "3fa0cd96-eef1-5676-8a61-b3b8758bbffb"

[[deps.Random]]
deps = ["SHA"]
uuid = "9a3f8284-a2c9-5f02-9a11-845980a1fd5c"

[[deps.ReadableRegex]]
git-tree-sha1 = "befcfa33f50688319571a770be4a55114b71d70a"
uuid = "cbbcb084-453d-4c4c-b292-e315607ba6a4"
version = "0.3.2"

[[deps.Readline_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Ncurses_jll"]
git-tree-sha1 = "9d70e0c890a6c7ca3eb1ca0eaabba4d34795b7fb"
uuid = "05236dd9-4125-5232-aa7c-9ec0c9b2c25a"
version = "8.2.1+0"

[[deps.Reexport]]
git-tree-sha1 = "45e428421666073eab6f2da5c9d310d99bb12f9b"
uuid = "189a3867-3050-52da-a836-e630ba90ab69"
version = "1.2.2"

[[deps.Requires]]
deps = ["UUIDs"]
git-tree-sha1 = "838a3a4188e2ded87a4f9f184b4b0d78a1e91cb7"
uuid = "ae029012-a4dd-5104-9daa-d747884805df"
version = "1.3.0"

[[deps.SCIP]]
deps = ["Libdl", "LinearAlgebra", "MathOptInterface", "OpenBLAS32_jll", "SCIP_PaPILO_jll", "SCIP_jll"]
git-tree-sha1 = "3d6a6516d6940a93b732e8ec7127652a0ead89c6"
uuid = "82193955-e24f-5292-bf16-6f2c5261a85f"
version = "0.11.14"

[[deps.SCIP_PaPILO_jll]]
deps = ["Artifacts", "Bzip2_jll", "CompilerSupportLibraries_jll", "GMP_jll", "Ipopt_jll", "JLLWrappers", "Libdl", "OpenBLAS32_jll", "Readline_jll", "Zlib_jll", "bliss_jll", "boost_jll", "oneTBB_jll"]
git-tree-sha1 = "c3cc2d09a8383a5dd01f136e4f398150921dae00"
uuid = "fc9abe76-a5e6-5fed-b0b7-a12f309cf031"
version = "800.100.0+0"

[[deps.SCIP_jll]]
deps = ["Artifacts", "Bzip2_jll", "CompilerSupportLibraries_jll", "GMP_jll", "Ipopt_jll", "JLLWrappers", "Libdl", "Readline_jll", "Zlib_jll", "bliss_jll", "boost_jll"]
git-tree-sha1 = "08f085b6144c47099ed81f564576530ce529ae87"
uuid = "e5ac4fe4-a920-5659-9bf8-f9f73e9e79ce"
version = "800.100.0+1"

[[deps.SHA]]
uuid = "ea8e919c-243c-51af-8825-aaa63cd721ce"
version = "0.7.0"

[[deps.SPRAL_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "Hwloc_jll", "JLLWrappers", "Libdl", "METIS_jll", "libblastrampoline_jll"]
git-tree-sha1 = "d1ca34081034a9c6903cfbe068a952a739c2aa5c"
uuid = "319450e9-13b8-58e8-aa9f-8fd1420848ab"
version = "2023.8.2+0"

[[deps.Scratch]]
deps = ["Dates"]
git-tree-sha1 = "3bac05bc7e74a75fd9cba4295cde4045d9fe2386"
uuid = "6c6a2e73-6563-6170-7368-637461726353"
version = "1.2.1"

[[deps.SentinelArrays]]
deps = ["Dates", "Random"]
git-tree-sha1 = "0e7508ff27ba32f26cd459474ca2ede1bc10991f"
uuid = "91c51154-3ec4-41a3-a24f-3f23e20d615c"
version = "1.4.1"

[[deps.Serialization]]
uuid = "9e88b42a-f829-5b0c-bbe9-9e923198166b"

[[deps.SharedArrays]]
deps = ["Distributed", "Mmap", "Random", "Serialization"]
uuid = "1a1011a3-84de-559e-8e89-a11a2f7dc383"

[[deps.SimpleBufferStream]]
git-tree-sha1 = "874e8867b33a00e784c8a7e4b60afe9e037b74e1"
uuid = "777ac1f9-54b0-4bf8-805c-2214025038e7"
version = "1.1.0"

[[deps.SimpleTraits]]
deps = ["InteractiveUtils", "MacroTools"]
git-tree-sha1 = "5d7e3f4e11935503d3ecaf7186eac40602e7d231"
uuid = "699a6c99-e7fa-54fc-8d76-47d257e15c1d"
version = "0.9.4"

[[deps.SimpleWeightedGraphs]]
deps = ["Graphs", "LinearAlgebra", "Markdown", "SparseArrays"]
git-tree-sha1 = "4b33e0e081a825dbfaf314decf58fa47e53d6acb"
uuid = "47aef6b3-ad0c-573a-a1e2-d07658019622"
version = "1.4.0"

[[deps.Sockets]]
uuid = "6462fe0b-24de-5631-8697-dd941f90decc"

[[deps.SortingAlgorithms]]
deps = ["DataStructures"]
git-tree-sha1 = "66e0a8e672a0bdfca2c3f5937efb8538b9ddc085"
uuid = "a2af1166-a08f-5f64-846c-94a0d3cef48c"
version = "1.2.1"

[[deps.SparseArrays]]
deps = ["Libdl", "LinearAlgebra", "Random", "Serialization", "SuiteSparse_jll"]
uuid = "2f01184e-e22b-5df5-ae63-d93ebab69eaf"
version = "1.10.0"

[[deps.SpatialIndexing]]
git-tree-sha1 = "84efe17c77e1f2156a7a0d8a7c163c1e1c7bdaed"
uuid = "d4ead438-fe20-5cc5-a293-4fd39a41b74c"
version = "0.1.6"

[[deps.SpecialFunctions]]
deps = ["IrrationalConstants", "LogExpFunctions", "OpenLibm_jll", "OpenSpecFun_jll"]
git-tree-sha1 = "2f5d4697f21388cbe1ff299430dd169ef97d7e14"
uuid = "276daf66-3868-5448-9aa4-cd146d93841b"
version = "2.4.0"

    [deps.SpecialFunctions.extensions]
    SpecialFunctionsChainRulesCoreExt = "ChainRulesCore"

    [deps.SpecialFunctions.weakdeps]
    ChainRulesCore = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"

[[deps.StaticArrays]]
deps = ["LinearAlgebra", "PrecompileTools", "Random", "StaticArraysCore"]
git-tree-sha1 = "bf074c045d3d5ffd956fa0a461da38a44685d6b2"
uuid = "90137ffa-7385-5640-81b9-e52037218182"
version = "1.9.3"

    [deps.StaticArrays.extensions]
    StaticArraysChainRulesCoreExt = "ChainRulesCore"
    StaticArraysStatisticsExt = "Statistics"

    [deps.StaticArrays.weakdeps]
    ChainRulesCore = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"
    Statistics = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"

[[deps.StaticArraysCore]]
git-tree-sha1 = "36b3d696ce6366023a0ea192b4cd442268995a0d"
uuid = "1e83bf80-4336-4d27-bf5d-d5a4f845583c"
version = "1.4.2"

[[deps.StaticGraphs]]
deps = ["Graphs", "JLD2", "SparseArrays"]
git-tree-sha1 = "855371d8fdfaed46dbb32a7c57a42db4441b9247"
uuid = "4c8beaf5-199b-59a0-a7f2-21d17de635b6"
version = "0.3.0"

[[deps.Statistics]]
deps = ["LinearAlgebra", "SparseArrays"]
uuid = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"
version = "1.10.0"

[[deps.StatsAPI]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "1ff449ad350c9c4cbc756624d6f8a8c3ef56d3ed"
uuid = "82ae8749-77ed-4fe6-ae5f-f523153014b0"
version = "1.7.0"

[[deps.StatsBase]]
deps = ["DataAPI", "DataStructures", "LinearAlgebra", "LogExpFunctions", "Missings", "Printf", "Random", "SortingAlgorithms", "SparseArrays", "Statistics", "StatsAPI"]
git-tree-sha1 = "d1bf48bfcc554a3761a133fe3a9bb01488e06916"
uuid = "2913bbd2-ae8a-5f71-8c99-4fb6c76f3a91"
version = "0.33.21"

[[deps.StringManipulation]]
deps = ["PrecompileTools"]
git-tree-sha1 = "a04cabe79c5f01f4d723cc6704070ada0b9d46d5"
uuid = "892a3eda-7b42-436c-8928-eab12a02cf0e"
version = "0.3.4"

[[deps.StructArrays]]
deps = ["ConstructionBase", "DataAPI", "Tables"]
git-tree-sha1 = "f4dc295e983502292c4c3f951dbb4e985e35b3be"
uuid = "09ab397b-f2b6-538f-b94a-2f83cf4a842a"
version = "0.6.18"

    [deps.StructArrays.extensions]
    StructArraysAdaptExt = "Adapt"
    StructArraysGPUArraysCoreExt = "GPUArraysCore"
    StructArraysSparseArraysExt = "SparseArrays"
    StructArraysStaticArraysExt = "StaticArrays"

    [deps.StructArrays.weakdeps]
    Adapt = "79e6a3ab-5dfb-504d-930d-738a2a938a0e"
    GPUArraysCore = "46192b85-c4d5-4398-a991-12ede77f4527"
    SparseArrays = "2f01184e-e22b-5df5-ae63-d93ebab69eaf"
    StaticArrays = "90137ffa-7385-5640-81b9-e52037218182"

[[deps.StructTypes]]
deps = ["Dates", "UUIDs"]
git-tree-sha1 = "ca4bccb03acf9faaf4137a9abc1881ed1841aa70"
uuid = "856f2bd8-1eba-4b0a-8007-ebc267875bd4"
version = "1.10.0"

[[deps.SuiteSparse_jll]]
deps = ["Artifacts", "Libdl", "libblastrampoline_jll"]
uuid = "bea87d4a-7f5b-5778-9afe-8cc45184846c"
version = "7.2.1+1"

[[deps.TOML]]
deps = ["Dates"]
uuid = "fa267f1f-6049-4f14-aa54-33bafae1ed76"
version = "1.0.3"

[[deps.TableTraits]]
deps = ["IteratorInterfaceExtensions"]
git-tree-sha1 = "c06b2f539df1c6efa794486abfb6ed2022561a39"
uuid = "3783bdb8-4a98-5b6b-af9a-565f29a5fe9c"
version = "1.0.1"

[[deps.Tables]]
deps = ["DataAPI", "DataValueInterfaces", "IteratorInterfaceExtensions", "LinearAlgebra", "OrderedCollections", "TableTraits"]
git-tree-sha1 = "cb76cf677714c095e535e3501ac7954732aeea2d"
uuid = "bd369af6-aec1-5ad0-b16a-f7cc5008161c"
version = "1.11.1"

[[deps.Tar]]
deps = ["ArgTools", "SHA"]
uuid = "a4e569a6-e804-4fa4-b0f3-eef7a1d5b13e"
version = "1.10.0"

[[deps.TensorCore]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "1feb45f88d133a655e001435632f019a9a1bcdb6"
uuid = "62fd8b95-f654-4bbd-a8a5-9c27f68ccd50"
version = "0.1.1"

[[deps.Test]]
deps = ["InteractiveUtils", "Logging", "Random", "Serialization"]
uuid = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

[[deps.TranscodingStreams]]
git-tree-sha1 = "5d54d076465da49d6746c647022f3b3674e64156"
uuid = "3bb67fe8-82b1-5028-8e26-92a6c54297fa"
version = "0.10.8"
weakdeps = ["Random", "Test"]

    [deps.TranscodingStreams.extensions]
    TestExt = ["Test", "Random"]

[[deps.TravelingSalesmanExact]]
deps = ["Clustering", "JuMP", "LinearAlgebra", "Logging", "MathOptInterface", "Printf", "TravelingSalesmanHeuristics", "UnicodePlots"]
git-tree-sha1 = "b931dde00e8d007008df17b1640567bd897b7c5b"
uuid = "737fac7d-4440-55ef-927e-002196e95561"
version = "0.3.11"

[[deps.TravelingSalesmanHeuristics]]
deps = ["LinearAlgebra", "Random"]
git-tree-sha1 = "723b16cbc89f37986f09a374cc35efca3ff89a23"
uuid = "8c8f4381-2cdd-507c-846c-be2bcff6f45f"
version = "0.3.4"

[[deps.Tricks]]
git-tree-sha1 = "eae1bb484cd63b36999ee58be2de6c178105112f"
uuid = "410a4b4d-49e4-4fbc-ab6d-cb71b17b3775"
version = "0.1.8"

[[deps.URIs]]
git-tree-sha1 = "67db6cc7b3821e19ebe75791a9dd19c9b1188f2b"
uuid = "5c2747f8-b7ea-4ff2-ba2e-563bfd36b1d4"
version = "1.5.1"

[[deps.UUIDs]]
deps = ["Random", "SHA"]
uuid = "cf7118a7-6976-5b1a-9a39-7adc72f591a4"

[[deps.UnPack]]
git-tree-sha1 = "387c1f73762231e86e0c9c5443ce3b4a0a9a0c2b"
uuid = "3a884ed6-31ef-47d7-9d2a-63182c4928ed"
version = "1.0.2"

[[deps.Unicode]]
uuid = "4ec0a83e-493e-50e2-b9ac-8f72acf5a8f5"

[[deps.UnicodePlots]]
deps = ["ColorTypes", "Contour", "Crayons", "Dates", "FileIO", "FreeTypeAbstraction", "LazyModules", "LinearAlgebra", "MarchingCubes", "NaNMath", "Printf", "SparseArrays", "StaticArrays", "StatsBase", "Unitful"]
git-tree-sha1 = "ae67ab0505b9453655f7d5ea65183a1cd1b3cfa0"
uuid = "b8865327-cd53-5732-bb35-84acbb429228"
version = "2.12.4"

[[deps.Unitful]]
deps = ["Dates", "LinearAlgebra", "Random"]
git-tree-sha1 = "dd260903fdabea27d9b6021689b3cd5401a57748"
uuid = "1986cc42-f94f-5a68-af5c-568840ba703d"
version = "1.20.0"

    [deps.Unitful.extensions]
    ConstructionBaseUnitfulExt = "ConstructionBase"
    InverseFunctionsUnitfulExt = "InverseFunctions"

    [deps.Unitful.weakdeps]
    ConstructionBase = "187b0558-2788-49d3-abe0-74a17ed4e7c9"
    InverseFunctions = "3587e190-3f89-42d0-90ee-14403ec27112"

[[deps.UnsafePointers]]
git-tree-sha1 = "c81331b3b2e60a982be57c046ec91f599ede674a"
uuid = "e17b2a0c-0bdf-430a-bd0c-3a23cae4ff39"
version = "1.0.0"

[[deps.XML2_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Libiconv_jll", "Zlib_jll"]
git-tree-sha1 = "532e22cf7be8462035d092ff21fada7527e2c488"
uuid = "02c8fc9c-b97f-50b9-bbe4-9be30ff0a78a"
version = "2.12.6+0"

[[deps.Zlib_jll]]
deps = ["Libdl"]
uuid = "83775a58-1f1d-513f-b197-d71354ab007a"
version = "1.2.13+1"

[[deps.bliss_jll]]
deps = ["Artifacts", "GMP_jll", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "f8b75e896a326a162a4f6e998990521d8302c810"
uuid = "508c9074-7a14-5c94-9582-3d4bc1871065"
version = "0.77.0+1"

[[deps.boost_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Zlib_jll"]
git-tree-sha1 = "72f8f9628f7f008e2616fe4c32ceb96bc82da733"
uuid = "28df3c45-c428-5900-9ff8-a3135698ca75"
version = "1.79.0+0"

[[deps.libblastrampoline_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "8e850b90-86db-534c-a0d3-1478176c7d93"
version = "5.8.0+1"

[[deps.micromamba_jll]]
deps = ["Artifacts", "JLLWrappers", "LazyArtifacts", "Libdl"]
git-tree-sha1 = "b4a5a3943078f9fd11ae0b5ab1bdbf7718617945"
uuid = "f8abcde7-e9b7-5caa-b8af-a437887ae8e4"
version = "1.5.8+0"

[[deps.nghttp2_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "8e850ede-7688-5339-a07c-302acd2aaf8d"
version = "1.52.0+1"

[[deps.oneTBB_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl"]
git-tree-sha1 = "7d0ea0f4895ef2f5cb83645fa689e52cb55cf493"
uuid = "1317d2d5-d96f-522e-a858-c73665f53c3e"
version = "2021.12.0+0"

[[deps.p7zip_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "3f19e933-33d8-53b3-aaab-bd5110c3b7a0"
version = "17.4.0+2"
"""

# ╔═╡ Cell order:
# ╟─915bd223-4b6e-441b-a82c-05d680cc93cb
# ╟─38b70851-9587-457d-adca-50394b3f6a98
# ╠═fc4454f6-1c07-4706-ac3f-040d9ee83994
# ╟─f1344329-8d08-4d5a-bb81-13ccc50ca6ba
# ╠═9a1222aa-110c-11ef-1d54-eb155df43b97
# ╠═012f104b-d3a1-4f2a-b224-86d1a711c7f4
# ╠═acb28c38-1914-4398-84b5-1288260845bb
# ╠═8d135017-37a8-457b-ab33-e4514e223e09
# ╠═021af38e-3860-4474-a901-620fc92f5d57
# ╠═9c316980-9940-4714-9ef9-357658a23479
# ╠═bcc30610-7e29-4d70-8ae1-752681659e5f
# ╟─d31c3579-f6c1-4959-b5d8-ca38f29d119c
# ╠═ada082b3-6615-45e9-818f-26e6f63f12ac
# ╠═1ac39fd7-fab9-4f22-a91b-944a69e67260
# ╠═c9f6c975-d9d0-4ad3-9f9a-4dacda0bb79c
# ╠═30812787-81a0-4f3d-9cd2-2df00c7c4ebd
# ╟─4fc5b1a8-9b33-486d-950a-4647d9993aff
# ╠═47126b71-1f25-4d73-bf91-22e39a84d2cc
# ╠═4741fe85-c011-451b-bef0-51cc487e978a
# ╠═951bfa51-da39-437c-9be2-e44648a1b868
# ╠═715a5564-81b1-4189-84ed-c9775f438b0f
# ╠═0f31dd19-bb4e-47fc-8566-645062b209c0
# ╠═8af5b693-f17d-44b4-b49f-7786b6e9f636
# ╠═8a55f364-495e-467f-9ca4-fa35e0318388
# ╠═7bf4ae79-5ba5-46ae-8cfa-a198fd6b4312
# ╠═e5c28754-3322-4436-9a30-ff5a95ec9ce9
# ╠═91585a4c-e842-4a87-ae02-ce9e86c3da37
# ╠═2f12547c-4be1-4644-85b7-c3fbdfcedf20
# ╟─568cc195-023c-4df3-a9fb-65f27ea534c5
# ╠═4401458c-3535-47c6-b219-c62c101920af
# ╟─efcf7447-bec3-4199-a54c-d8cf1c9874ad
# ╠═542b52d9-9f83-49d4-98e1-be2d4c5870a9
# ╠═a868a31f-2cc7-4283-b0e6-27c50f43a3be
# ╠═63333464-4a87-4b14-9507-57cbcdd3d734
# ╠═5a635ea7-a3e7-4608-b7db-065588a0d732
# ╠═0bf52f3a-cacd-4310-9526-2610ef1235bb
# ╠═39fe4d23-0e0c-4203-a026-db8fbe275815
# ╠═013924bf-76ff-451b-b45b-965d020a9564
# ╠═e7b7eddc-ddde-4554-8b11-1785e381fd0e
# ╠═26fa54e2-864c-417d-a44b-fb20550cebb2
# ╠═b136349f-c4b2-4cc8-88c2-99e2bb1688c2
# ╠═a67b7b91-3447-4874-864e-5cae0edf4d96
# ╠═e10130dc-8720-4920-b13e-a3f849e238b1
# ╠═e1eabfe7-ae82-4007-abb7-59681bb7bf90
# ╠═35ae7286-7037-4551-ae18-557811fb9488
# ╟─00000000-0000-0000-0000-000000000001
# ╟─00000000-0000-0000-0000-000000000002
