//! Middleware de rate limiting baseado em IP usando `governor`.

use std::{
    net::SocketAddr,
    num::NonZeroU32,
    sync::Arc,
    task::{Context, Poll},
    time::Duration,
};

use axum::{
    body::Body,
    extract::ConnectInfo,
    http::{Request, StatusCode},
    response::Response,
};
use futures::future::BoxFuture;
use governor::{clock::DefaultClock, state::keyed::DefaultKeyedStateStore, Quota, RateLimiter};
use tower::{Layer, Service};

type GovernorLimiter = RateLimiter<SocketAddr, DefaultKeyedStateStore<SocketAddr>, DefaultClock>;

/// Camada que aplica rate limiting por endereço IP.
#[derive(Clone)]
pub struct RateLimitLayer {
    limiter: Arc<GovernorLimiter>,
}

impl RateLimitLayer {
    /// Cria uma nova camada com limite `requests` a cada `per`.
    pub fn new(requests: NonZeroU32, per: Duration) -> Self {
        let quota = Quota::with_period(per)
            .expect("period must be non-zero")
            .allow_burst(requests);

        Self {
            limiter: Arc::new(GovernorLimiter::keyed(quota)),
        }
    }
}

impl<S> Layer<S> for RateLimitLayer {
    type Service = RateLimitService<S>;

    fn layer(&self, inner: S) -> Self::Service {
        RateLimitService {
            inner,
            limiter: self.limiter.clone(),
        }
    }
}

/// Serviço que aplica rate limiting de forma stateful.
pub struct RateLimitService<S> {
    inner: S,
    limiter: Arc<GovernorLimiter>,
}

impl<S> Clone for RateLimitService<S>
where
    S: Clone,
{
    fn clone(&self) -> Self {
        Self {
            inner: self.inner.clone(),
            limiter: self.limiter.clone(),
        }
    }
}

impl<S, B> Service<Request<B>> for RateLimitService<S>
where
    S: Service<Request<B>, Response = Response> + Clone + Send + 'static,
    S::Future: Send + 'static,
    S::Error: Into<axum::BoxError>,
    B: Send + 'static,
{
    type Response = S::Response;
    type Error = S::Error;
    type Future = BoxFuture<'static, Result<Self::Response, Self::Error>>;

    fn poll_ready(&mut self, cx: &mut Context<'_>) -> Poll<Result<(), Self::Error>> {
        self.inner.poll_ready(cx)
    }

    fn call(&mut self, req: Request<B>) -> Self::Future {
        let limiter = self.limiter.clone();
        let mut inner = self.inner.clone();

        Box::pin(async move {
            let client_addr = extract_ip(&req);

            if limiter.check_key(&client_addr).is_err() {
                let response = Response::builder()
                    .status(StatusCode::TOO_MANY_REQUESTS)
                    .body(Body::from("Rate limit exceeded"))
                    .expect("resposta válida");
                return Ok(response);
            }

            inner.call(req).await
        })
    }
}

fn extract_ip<B>(req: &Request<B>) -> SocketAddr {
    req.extensions()
        .get::<ConnectInfo<SocketAddr>>()
        .map(|info| info.0)
        .unwrap_or_else(|| SocketAddr::from(([0, 0, 0, 0], 0)))
}
