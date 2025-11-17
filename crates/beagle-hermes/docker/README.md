# HERMES BPSE - Docker Deployment

## Quick Start

### Development

```bash
# Build image
docker build -f docker/Dockerfile -t hermes:dev .

# Run with docker-compose
docker compose -f docker-compose.observability.yml up -d
docker compose -f docker/docker-compose.prod.yml up -d
```

### Production

```bash
# Pull from GitHub Container Registry
docker pull ghcr.io/agourakis82/beagle/hermes:latest

# Run with production compose
docker compose -f docker/docker-compose.prod.yml up -d
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `DATABASE_URL` | PostgreSQL connection string | `postgresql://postgres:postgres@postgres:5432/beagle` |
| `NEO4J_URI` | Neo4j connection URI | `neo4j://neo4j:7687` |
| `NEO4J_USER` | Neo4j username | `neo4j` |
| `NEO4J_PASSWORD` | Neo4j password | `hermespassword` |
| `REDIS_URL` | Redis connection URL | `redis://redis:6379` |
| `OPENAI_API_KEY` | OpenAI API key (for Whisper) | - |
| `JWT_SECRET` | JWT signing secret | `change-me-in-production` |
| `RUST_LOG` | Logging level | `info` |

## Health Checks

- **API**: `http://localhost:8080/health`
- **Metrics**: `http://localhost:9090/metrics`

## Volumes

- `/data`: Persistent data storage
- `/logs`: Application logs

## Multi-Stage Build

The Dockerfile uses a multi-stage build:

1. **Builder stage**: Compiles Rust code and installs Python dependencies
2. **Runtime stage**: Minimal Debian image with only runtime dependencies

This results in a smaller final image (~500MB vs ~2GB).

## CI/CD Integration

The Docker image is automatically built and pushed to GitHub Container Registry on:
- Push to `main` branch → `ghcr.io/agourakis82/beagle/hermes:main`
- Push to `develop` branch → `ghcr.io/agourakis82/beagle/hermes:develop`
- Tagged releases → `ghcr.io/agourakis82/beagle/hermes:v1.0.0`

## Troubleshooting

### Container won't start

```bash
# Check logs
docker logs hermes-bpse

# Check health
docker inspect hermes-bpse | jq '.[0].State.Health'
```

### Dependencies not ready

The entrypoint script waits for dependencies. If it times out:

```bash
# Check dependency containers
docker ps | grep -E "postgres|neo4j|redis"

# Test connectivity
docker exec hermes-bpse curl http://postgres:5432
docker exec hermes-bpse nc -zv neo4j 7687
docker exec hermes-bpse nc -zv redis 6379
```

