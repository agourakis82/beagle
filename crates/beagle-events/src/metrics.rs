use prometheus::{Counter, Histogram, HistogramOpts, IntGauge, Registry};

lazy_static::lazy_static! {
    static ref EVENTS_PUBLISHED: Counter = Counter::new(
        "beagle_events_published_total",
        "Total number of events published"
    ).unwrap();

    static ref EVENTS_CONSUMED: Counter = Counter::new(
        "beagle_events_consumed_total",
        "Total number of events consumed"
    ).unwrap();

    static ref PUBLISH_DURATION: Histogram = Histogram::with_opts(
        HistogramOpts::new(
            "beagle_event_publish_duration_seconds",
            "Event publish duration"
        )
    ).unwrap();

    static ref ACTIVE_SUBSCRIBERS: IntGauge = IntGauge::new(
        "beagle_active_subscribers",
        "Number of active event subscribers"
    ).unwrap();
}

/// Metrics registry
pub struct EventMetrics {
    registry: Registry,
}

impl EventMetrics {
    pub fn new() -> Self {
        let registry = Registry::new();

        registry
            .register(Box::new(EVENTS_PUBLISHED.clone()))
            .unwrap();
        registry
            .register(Box::new(EVENTS_CONSUMED.clone()))
            .unwrap();
        registry
            .register(Box::new(PUBLISH_DURATION.clone()))
            .unwrap();
        registry
            .register(Box::new(ACTIVE_SUBSCRIBERS.clone()))
            .unwrap();

        Self { registry }
    }

    pub fn registry(&self) -> &Registry {
        &self.registry
    }

    pub fn inc_published() {
        EVENTS_PUBLISHED.inc();
    }

    pub fn inc_consumed() {
        EVENTS_CONSUMED.inc();
    }

    pub fn observe_publish_duration(duration_secs: f64) {
        PUBLISH_DURATION.observe(duration_secs);
    }

    pub fn set_active_subscribers(count: i64) {
        ACTIVE_SUBSCRIBERS.set(count);
    }
}

impl Default for EventMetrics {
    fn default() -> Self {
        Self::new()
    }
}
