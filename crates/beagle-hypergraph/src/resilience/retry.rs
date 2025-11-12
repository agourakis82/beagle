//! Política de retentativas exponenciais com circuit breaker assíncrono.
//!
//! Este módulo implementa uma estratégia de _retry_ com _exponential backoff_
//! acoplada a um *circuit breaker* não bloqueante, adequada para cenários onde
//! operações idempotentes sofrem falhas transientes (por exemplo, chamadas
//! a serviços remotos ou consultas a bancos temporariamente instáveis).
//!
//! A política padrão realiza três tentativas com atrasos de `100 ms`,
//! `200 ms` e `400 ms`, respectivamente. O *breaker* é configurado para abrir
//! após duas falhas consecutivas, permanecendo indisponível por dois segundos
//! antes de migrar para o estado *half-open*. Nesse estado, uma sequência de
//! sucessos configurável fecha novamente o circuito.

use std::{fmt, sync::Arc, time::Duration};

use futures::future::BoxFuture;
use tokio::{
    sync::Mutex,
    time::{sleep, Instant},
};

/// Configuração principal da política de retentativas.
#[derive(Clone, Debug)]
pub struct RetryConfig {
    /// Número máximo de tentativas (mínimo de 1).
    pub max_attempts: usize,
    /// Atraso base utilizado no cálculo exponencial.
    pub base_delay: Duration,
    /// Limite superior aplicado ao atraso calculado.
    pub max_delay: Duration,
    /// Configuração do *circuit breaker* acoplado à política.
    pub circuit_breaker: CircuitBreakerConfig,
}

impl RetryConfig {
    fn validate(&self) {
        assert!(self.max_attempts > 0, "max_attempts deve ser >= 1");
        assert!(
            self.base_delay <= self.max_delay,
            "base_delay não pode exceder max_delay"
        );
        self.circuit_breaker.validate();
    }
}

impl Default for RetryConfig {
    fn default() -> Self {
        Self {
            max_attempts: 3,
            base_delay: Duration::from_millis(100),
            max_delay: Duration::from_millis(400),
            circuit_breaker: CircuitBreakerConfig::default(),
        }
    }
}

/// Configuração estrutural do *circuit breaker*.
#[derive(Clone, Debug)]
pub struct CircuitBreakerConfig {
    /// Número de falhas consecutivas necessárias para abrir o circuito.
    pub failure_threshold: usize,
    /// Tempo mínimo de abertura antes de transicionar para *half-open*.
    pub open_interval: Duration,
    /// Quantidade de sucessos consecutivos em *half-open* para fechar o circuito.
    pub half_open_success_threshold: usize,
}

impl CircuitBreakerConfig {
    fn validate(&self) {
        assert!(
            self.failure_threshold > 0,
            "failure_threshold deve ser >= 1"
        );
        assert!(
            self.open_interval > Duration::from_millis(0),
            "open_interval deve ser positivo"
        );
        assert!(
            self.half_open_success_threshold > 0,
            "half_open_success_threshold deve ser >= 1"
        );
    }
}

impl Default for CircuitBreakerConfig {
    fn default() -> Self {
        Self {
            failure_threshold: 2,
            open_interval: Duration::from_secs(2),
            half_open_success_threshold: 1,
        }
    }
}

/// Erros potenciais ao executar operações sob a política de retry.
#[derive(Debug)]
pub enum RetryError<E> {
    /// Todas as tentativas foram esgotadas mantendo o circuito fechado.
    Operation { attempts: usize, error: E },
    /// O circuito encontra-se aberto; opcionalmente carrega o último erro observado.
    CircuitOpen {
        remaining: Duration,
        last_error: Option<E>,
    },
}

impl<E: fmt::Debug> fmt::Display for RetryError<E> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Operation { attempts, .. } => write!(
                f,
                "Operação falhou após {} tentativas consecutivas",
                attempts
            ),
            Self::CircuitOpen { remaining, .. } => write!(
                f,
                "Circuit breaker aberto; aguarde aproximadamente {:?} para nova tentativa",
                remaining
            ),
        }
    }
}

impl<E> std::error::Error for RetryError<E> where E: fmt::Debug + Send + Sync + 'static {}

/// Política concreta de retentativas exponenciais com *circuit breaker*.
#[derive(Clone, Debug)]
pub struct RetryPolicy {
    config: RetryConfig,
    breaker: Arc<CircuitBreaker>,
}

impl RetryPolicy {
    /// Cria uma nova política validando os parâmetros fornecidos.
    pub fn new(config: RetryConfig) -> Self {
        config.validate();
        let breaker = Arc::new(CircuitBreaker::new(config.circuit_breaker.clone()));
        Self { config, breaker }
    }

    /// Executa uma operação assíncrona sob proteção de retentativas e *circuit breaker*.
    pub async fn execute<F, T, E>(&self, mut operation: F) -> Result<T, RetryError<E>>
    where
        F: FnMut() -> BoxFuture<'static, Result<T, E>>,
    {
        for attempt in 0..self.config.max_attempts {
            if let Err(remaining) = self.breaker.can_execute().await {
                return Err(RetryError::CircuitOpen {
                    remaining,
                    last_error: None,
                });
            }

            match operation().await {
                Ok(result) => {
                    self.breaker.record_success().await;
                    return Ok(result);
                }
                Err(error) => {
                    let transition = self.breaker.record_failure().await;
                    let is_last_attempt = attempt + 1 == self.config.max_attempts;

                    if let BreakerTransition::Opened { remaining } = transition {
                        return Err(RetryError::CircuitOpen {
                            remaining,
                            last_error: Some(error),
                        });
                    }

                    if is_last_attempt {
                        return Err(RetryError::Operation {
                            attempts: self.config.max_attempts,
                            error,
                        });
                    }

                    let delay = self.calculate_backoff(attempt);
                    sleep(delay).await;
                }
            }
        }

        unreachable!("loop deve retornar em sucesso ou erro")
    }

    fn calculate_backoff(&self, attempt: usize) -> Duration {
        let factor = if attempt >= 31 {
            u32::MAX
        } else {
            1u32 << attempt
        };
        match self.config.base_delay.checked_mul(factor) {
            Some(delay) => delay.min(self.config.max_delay),
            None => self.config.max_delay,
        }
    }
}

impl Default for RetryPolicy {
    fn default() -> Self {
        Self::new(RetryConfig::default())
    }
}

#[derive(Debug)]
struct CircuitBreaker {
    config: CircuitBreakerConfig,
    state: Mutex<BreakerState>,
}

impl CircuitBreaker {
    fn new(config: CircuitBreakerConfig) -> Self {
        let state = BreakerState::Closed {
            consecutive_failures: 0,
        };
        Self {
            config,
            state: Mutex::new(state),
        }
    }

    async fn can_execute(&self) -> Result<(), Duration> {
        let mut state = self.state.lock().await;
        match &mut *state {
            BreakerState::Closed { .. } => Ok(()),
            BreakerState::Open { opened_at } => {
                let elapsed = opened_at.elapsed();
                if elapsed >= self.config.open_interval {
                    *state = BreakerState::HalfOpen {
                        consecutive_successes: 0,
                    };
                    Ok(())
                } else {
                    Err(self.config.open_interval.saturating_sub(elapsed))
                }
            }
            BreakerState::HalfOpen { .. } => Ok(()),
        }
    }

    async fn record_success(&self) {
        let mut state = self.state.lock().await;
        match &mut *state {
            BreakerState::Closed {
                consecutive_failures,
            } => {
                *consecutive_failures = 0;
            }
            BreakerState::HalfOpen {
                consecutive_successes,
            } => {
                *consecutive_successes += 1;
                if *consecutive_successes >= self.config.half_open_success_threshold {
                    *state = BreakerState::Closed {
                        consecutive_failures: 0,
                    };
                }
            }
            BreakerState::Open { .. } => {
                *state = BreakerState::Closed {
                    consecutive_failures: 0,
                };
            }
        }
    }

    async fn record_failure(&self) -> BreakerTransition {
        let mut state = self.state.lock().await;
        match &mut *state {
            BreakerState::Closed {
                consecutive_failures,
            } => {
                *consecutive_failures += 1;
                if *consecutive_failures >= self.config.failure_threshold {
                    *state = BreakerState::Open {
                        opened_at: Instant::now(),
                    };
                    BreakerTransition::Opened {
                        remaining: self.config.open_interval,
                    }
                } else {
                    BreakerTransition::StillClosed
                }
            }
            BreakerState::HalfOpen { .. } => {
                *state = BreakerState::Open {
                    opened_at: Instant::now(),
                };
                BreakerTransition::Opened {
                    remaining: self.config.open_interval,
                }
            }
            BreakerState::Open { opened_at } => {
                let elapsed = opened_at.elapsed();
                BreakerTransition::Opened {
                    remaining: self.config.open_interval.saturating_sub(elapsed),
                }
            }
        }
    }
}

#[derive(Debug)]
enum BreakerState {
    Closed { consecutive_failures: usize },
    Open { opened_at: Instant },
    HalfOpen { consecutive_successes: usize },
}

#[derive(Debug, PartialEq, Eq)]
enum BreakerTransition {
    StillClosed,
    Opened { remaining: Duration },
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::error::Error;

    #[derive(Debug, Clone)]
    struct TestError(&'static str);

    impl fmt::Display for TestError {
        fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
            write!(f, "{}", self.0)
        }
    }

    impl Error for TestError {}

    #[test]
    fn calculate_backoff_respeita_exponencial_e_teto() {
        let policy = RetryPolicy::default();
        assert_eq!(policy.calculate_backoff(0), Duration::from_millis(100));
        assert_eq!(policy.calculate_backoff(1), Duration::from_millis(200));
        assert_eq!(policy.calculate_backoff(2), Duration::from_millis(400));
        assert_eq!(policy.calculate_backoff(3), Duration::from_millis(400));
    }

    #[tokio::test]
    async fn sucesso_apos_falhas_reseta_breaker() {
        let mut config = RetryConfig::default();
        config.base_delay = Duration::from_millis(5);
        config.max_delay = Duration::from_millis(20);
        config.circuit_breaker.open_interval = Duration::from_millis(50);

        let policy = RetryPolicy::new(config);
        let mut attempts = 0usize;

        let result = policy
            .execute(|| {
                attempts += 1;
                let current = attempts;
                Box::pin(async move {
                    if current < 3 {
                        Err(TestError("falha transitória"))
                    } else {
                        Ok(current)
                    }
                })
            })
            .await;

        assert_eq!(result.unwrap(), 3);

        // Após sucesso, o circuito deve estar fechado e aceitar novas execuções.
        let final_result = policy
            .execute(|| Box::pin(async { Ok::<_, TestError>(42) }))
            .await;
        assert_eq!(final_result.unwrap(), 42);
    }

    #[tokio::test]
    async fn circuit_breaker_abre_e_rejeita_novas_execucoes() {
        let mut config = RetryConfig::default();
        config.max_attempts = 5;
        config.base_delay = Duration::from_millis(1);
        config.max_delay = Duration::from_millis(4);
        config.circuit_breaker.failure_threshold = 2;
        config.circuit_breaker.open_interval = Duration::from_millis(100);

        let policy = RetryPolicy::new(config);

        let first = policy
            .execute(|| Box::pin(async { Err::<(), _>(TestError("falha dura")) }))
            .await;

        match first.unwrap_err() {
            RetryError::CircuitOpen {
                remaining,
                last_error: Some(err),
            } => {
                assert!(remaining <= Duration::from_millis(100));
                assert_eq!(err.0, "falha dura");
            }
            other => panic!("esperava CircuitOpen, obtido {:?}", other),
        }

        // Tentativa imediata deve ser rejeitada antes de executar a operação.
        let second = policy
            .execute(|| Box::pin(async { Ok::<(), TestError>(()) }))
            .await;

        match second.unwrap_err() {
            RetryError::CircuitOpen {
                remaining,
                last_error: None,
            } => {
                assert!(remaining <= Duration::from_millis(100));
            }
            other => panic!("esperava CircuitOpen (pré-execução), obtido {:?}", other),
        }

        // Aguarda janela de meia-vida e testa fechamento após sucesso em half-open.
        sleep(Duration::from_millis(110)).await;

        policy
            .execute(|| Box::pin(async { Ok::<_, TestError>("ok") }))
            .await
            .expect("half-open deveria aceitar a operação");
    }
}







