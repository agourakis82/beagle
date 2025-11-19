#!/usr/bin/env julia

"""
KEC Features Extractor - 100% Julia
Extrai features KEC de moléculas
"""

module KECFeatures

using Graphs
using LinearAlgebra

export extract_kec_features

function extract_kec_features(adj_matrix::Matrix{Float64})::Vector{Float64}
    n = size(adj_matrix, 1)
    n == 0 && return zeros(15)
    
    # Spectral entropy
    L = normalized_laplacian(adj_matrix)
    eigenvals = real.(eigen(L).values)
    eigenvals = abs.(eigenvals)
    p = eigenvals ./ sum(eigenvals)
    p = p[p .> 1e-15]
    spectral_entropy = -sum(p .* log.(p))
    
    # Forman curvature
    forman_curv = compute_forman_curvature(adj_matrix)
    
    # Clustering
    clustering = compute_clustering_coefficient(adj_matrix)
    
    # Small-world
    small_world = compute_small_world_index(adj_matrix)
    
    # Fractal dimension
    fractal_dim = compute_fractal_dimension(adj_matrix)
    
    # Features combinadas
    [
        spectral_entropy,
        forman_curv,
        clustering,
        small_world,
        fractal_dim,
        maximum(eigenvals),
        minimum(eigenvals),
        maximum(eigenvals) - minimum(eigenvals),
        mean(sum(adj_matrix, dims=2)),
        std(sum(adj_matrix, dims=2)),
        spectral_entropy * forman_curv,
        clustering * small_world,
        fractal_dim * spectral_entropy,
        mean(eigenvals),
        std(eigenvals)
    ]
end

function normalized_laplacian(A::Matrix{Float64})::Matrix{Float64}
    n = size(A, 1)
    degrees = sum(A, dims=2)
    D_inv_sqrt = diagm(0 => 1.0 ./ sqrt.(max.(degrees, 1e-12)))
    I = Matrix{Float64}(I, n, n)
    I - D_inv_sqrt * A * D_inv_sqrt
end

function compute_forman_curvature(A::Matrix{Float64})::Float64
    n = size(A, 1)
    curvature = 0.0
    count = 0
    
    for i in 1:n
        for j in (i+1):n
            if A[i, j] > 0
                deg_i = sum(A[i, :])
                deg_j = sum(A[j, :])
                triangles = sum(A[i, :] .* A[j, :])
                curvature += 4 - (deg_i + deg_j) + 3 * triangles
                count += 1
            end
        end
    end
    
    count > 0 ? curvature / count : 0.0
end

function compute_clustering_coefficient(A::Matrix{Float64})::Float64
    n = size(A, 1)
    total = 0.0
    
    for i in 1:n
        neighbors = findall(x -> x > 0, A[i, :])
        k = length(neighbors)
        k < 2 && continue
        
        triangles = 0
        for j in neighbors
            for l in neighbors
                if j < l && A[j, l] > 0
                    triangles += 1
                end
            end
        end
        
        total += triangles / (k * (k - 1) / 2)
    end
    
    n > 0 ? total / n : 0.0
end

function compute_small_world_index(A::Matrix{Float64})::Float64
    clustering = compute_clustering_coefficient(A)
    avg_path = compute_average_path_length(A)
    avg_path > 0 ? clustering / avg_path : 0.0
end

function compute_average_path_length(A::Matrix{Float64})::Float64
    n = size(A, 1)
    path_lengths = Float64[]
    
    for i in 1:min(100, n)
        distances = dijkstra(A, i)
        append!(path_lengths, filter(x -> x > 0 && x < Inf, distances))
    end
    
    length(path_lengths) > 0 ? mean(path_lengths) : 1.0
end

function dijkstra(A::Matrix{Float64}, start::Int)::Vector{Float64}
    n = size(A, 1)
    dist = fill(Inf, n)
    dist[start] = 0.0
    visited = falses(n)
    
    for _ in 1:n
        u = argmin([visited[i] ? Inf : dist[i] for i in 1:n])
        visited[u] = true
        
        for v in 1:n
            if A[u, v] > 0 && !visited[v]
                alt = dist[u] + A[u, v]
                if alt < dist[v]
                    dist[v] = alt
                end
            end
        end
    end
    
    dist
end

function compute_fractal_dimension(A::Matrix{Float64})::Float64
    n = size(A, 1)
    box_sizes = [1, 2, 4, 8, 16]
    box_counts = Int[]
    
    for box_size in box_sizes
        box_size >= n && continue
        count = count_boxes(A, box_size)
        push!(box_counts, count)
    end
    
    length(box_counts) < 2 && return 1.0
    
    log_sizes = log.(box_sizes[1:length(box_counts)])
    log_counts = log.(box_counts)
    
    c = cov(log_sizes, log_counts)
    v = var(log_sizes)
    v > 0 ? -c / v : 1.0
end

function count_boxes(A::Matrix{Float64}, box_size::Int)::Int
    n = size(A, 1)
    boxes = Set{Tuple{Int,Int}}()
    
    for i in 1:box_size:n
        for j in 1:box_size:n
            i_end = min(i + box_size - 1, n)
            j_end = min(j + box_size - 1, n)
            
            has_edge = false
            for x in i:i_end
                for y in j:j_end
                    if A[x, y] > 0
                        has_edge = true
                        break
                    end
                end
                has_edge && break
            end
            
            has_edge && push!(boxes, (i, j))
        end
    end
    
    length(boxes)
end

end # module

