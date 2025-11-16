FROM rust:1.75-alpine AS builder

RUN apk add --no-cache musl-dev

WORKDIR /app

COPY Cargo.toml Cargo.lock ./
COPY beagle-hypergraph ../beagle-hypergraph
COPY beagle-server ./beagle-server

RUN cargo build --release --bin beagle-server

FROM alpine:3.19

RUN apk add --no-cache ca-certificates

COPY --from=builder /app/target/release/beagle-server /usr/local/bin/

EXPOSE 3000

CMD ["beagle-server"]








