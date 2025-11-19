#!/usr/bin/env julia

module KEC3GPU

using CUDA
using Graphs
using LinearAlgebra
using SparseArrays
using Dates
using Statistics

export compute_all_metrics, Kec3Engine, EntropyResult, CurvatureResult

struct EntropyResult
    spectral_entropy::Float64
    lambda_max::Float64
    lambda_min::Float64
    spectral_gap::Float64
end

struct CurvatureResult
    forman_curvature::Float64
    ollivier_curvature::Float64
    ricci_curvature::Float64
end

struct Kec3Engine
    device::CUDA.CuDevice
end

function Kec3Engine()
    if CUDA.functional()
        device = CUDA.device()
        @info "🔧 KEC 3.0 Engine inicializado (GPU: $(CUDA.name(device)))"
        Kec3Engine(device)
    else
        @warn "⚠️  CUDA não disponível, usando CPU"
        Kec3Engine(CUDA.device(0))
    end
end

function normalized_laplacian(adj_matrix::Matrix{Float64})::Matrix{Float64}
    n = size(adj_matrix, 1)
    degrees = sum(adj_matrix, dims=2)
    D_inv_sqrt = diagm(0 => 1.0 ./ sqrt.(max.(degrees, 1e-12)))
    I = Matrix{Float64}(I, n, n)
    L = I - D_inv_sqrt * adj_matrix * D_inv_sqrt
    L
end

function spectral_entropy(adj_matrix::Matrix{Float64}, k::Int=64)::EntropyResult
    n = size(adj_matrix, 1)
    n == 0 && return EntropyResult(0.0, 0.0, 0.0, 0.0)
    
    L = normalized_laplacian(adj_matrix)
    
    if n > 128
        vals = real.(eigen(L).values)
        vals = abs.(vals)
        vals = sort(vals, rev=true)[1:min(k, length(vals))]
    else
        vals = real.(eigen(L).values)
        vals = abs.(vals)
    end
    
    s = sum(vals)
    p = s > 0 ? vals ./ s : ones(length(vals)) ./ length(vals)
    p = p[p .> 1e-15]
    
    H = -sum(p .* log.(p))
    
    EntropyResult(
        H,
        maximum(vals),
        minimum(vals),
        maximum(vals) - minimum(vals)
    )
end

function forman_curvature(adj_matrix::Matrix{Float64})::Float64
    n = size(adj_matrix, 1)
    curvature = 0.0
    
    for i in 1:n
        for j in (i+1):n
            if adj_matrix[i, j] > 0
                deg_i = sum(adj_matrix[i, :])
                deg_j = sum(adj_matrix[j, :])
                triangles = sum(adj_matrix[i, :] .* adj_matrix[j, :])
                curvature += 4 - (deg_i + deg_j) + 3 * triangles
            end
        end
    end
    
    curvature / (n * (n - 1) / 2)
end

function compute_all_metrics(engine::Kec3Engine, graph_data::Vector{Float64})::Dict{String,Float64}
    @info "📊 Computando métricas KEC 3.0"
    
    n = Int(sqrt(length(graph_data)))
    adj_matrix = reshape(graph_data, n, n)
    
    entropy_res = spectral_entropy(adj_matrix)
    forman_curv = forman_curvature(adj_matrix)
    
    degrees = sum(adj_matrix, dims=2)
    avg_degree = mean(degrees)
    clustering = compute_clustering(adj_matrix)
    
    metrics = Dict(
        "spectral_entropy" => entropy_res.spectral_entropy,
        "lambda_max" => entropy_res.lambda_max,
        "lambda_min" => entropy_res.lambda_min,
        "spectral_gap" => entropy_res.spectral_gap,
        "forman_curvature" => forman_curv,
        "average_degree" => avg_degree,
        "clustering_coefficient" => clustering,
        "small_world_index" => compute_small_world(adj_matrix),
        "fractal_dimension" => compute_fractal_dimension(adj_matrix),
        "topological_complexity" => entropy_res.spectral_entropy * forman_curv
    )
    
    @info "✅ Métricas KEC 3.0 computadas: $(length(metrics)) métricas"
    metrics
end

function compute_clustering(adj_matrix::Matrix{Float64})::Float64
    n = size(adj_matrix, 1)
    total = 0.0
    
    for i in 1:n
        neighbors = findall(x -> x > 0, adj_matrix[i, :])
        k = length(neighbors)
        k < 2 && continue
        
        triangles = 0
        for j in neighbors
            for l in neighbors
                if j < l && adj_matrix[j, l] > 0
                    triangles += 1
                end
            end
        end
        
        total += triangles / (k * (k - 1) / 2)
    end
    
    total / n
end

function compute_small_world(adj_matrix::Matrix{Float64})::Float64
    n = size(adj_matrix, 1)
    path_lengths = []
    
    for i in 1:min(100, n)
        distances = dijkstra_shortest_paths(adj_matrix, i)
        path_lengths = vcat(path_lengths, filter(x -> x > 0, distances))
    end
    
    avg_path = length(path_lengths) > 0 ? mean(path_lengths) : 1.0
    clustering = compute_clustering(adj_matrix)
    
    clustering / avg_path
end

function dijkstra_shortest_paths(adj_matrix::Matrix{Float64}, start::Int)::Vector{Float64}
    n = size(adj_matrix, 1)
    dist = fill(Inf, n)
    dist[start] = 0.0
    visited = falses(n)
    
    for _ in 1:n
        u = findmin([visited[i] ? Inf : dist[i] for i in 1:n])[2]
        visited[u] = true
        
        for v in 1:n
            if adj_matrix[u, v] > 0 && !visited[v]
                alt = dist[u] + adj_matrix[u, v]
                if alt < dist[v]
                    dist[v] = alt
                end
            end
        end
    end
    
    dist
end

function compute_fractal_dimension(adj_matrix::Matrix{Float64})::Float64
    n = size(adj_matrix, 1)
    box_sizes = [1, 2, 4, 8, 16]
    box_counts = []
    
    for box_size in box_sizes
        if box_size >= n
            continue
        end
        count = count_boxes(adj_matrix, box_size)
        push!(box_counts, count)
    end
    
    if length(box_counts) < 2
        return 1.0
    end
    
    log_sizes = log.(box_sizes[1:length(box_counts)])
    log_counts = log.(box_counts)
    
    if length(log_sizes) < 2
        return 1.0
    end
    
    c = cov(log_sizes, log_counts)
    v = var(log_sizes)
    v > 0 ? -c / v : 1.0
end

function count_boxes(adj_matrix::Matrix{Float64}, box_size::Int)::Int
    n = size(adj_matrix, 1)
    boxes = Set{Tuple{Int,Int}}()
    
    for i in 1:box_size:n
        for j in 1:box_size:n
            i_end = min(i + box_size - 1, n)
            j_end = min(j + box_size - 1, n)
            
            has_edge = false
            for x in i:i_end
                for y in j:j_end
                    if adj_matrix[x, y] > 0
                        has_edge = true
                        break
                    end
                end
                has_edge && break
            end
            
            if has_edge
                push!(boxes, (i, j))
            end
        end
    end
    
    length(boxes)
end

end # module
