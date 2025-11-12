//! Carregamento e gestão da configuração do servidor Beagle.

use std::time::Duration;

use anyhow::{anyhow, Context, Result};
use argon2::{password_hash::{rand_core::OsRng, PasswordHasher, SaltString}, Argon2};
use config::{Environment, File};

/// Configuração completa para o servidor REST.
#[derive(Clone, Debug)]
pub struct Config {
    host: String,
    port: u16,
    database_url: String,
    redis_url: String,
    jwt_secret: String,
    jwt_expiration_hours: i64,
    admin_username: String,
    admin_password_hash: String,
    rate_limit_requests_per_minute: u32,
}

impl Config {
    /// Carrega configuração a partir de variáveis de ambiente (.env incluso).
    pub fn from_env() -> Result<Self> {
        let mut builder = config::Config::builder().add_source(
            Environment::default()
                .separator("__")
                .try_parsing(true)
                .with_list_parse_key("ALLOWED_ORIGINS"),
        );

        // Permite carregar arquivos opcionais se especificados.
        if let Ok(config_path) = std::env::var("BEAGLE_CONFIG_FILE") {
            builder = builder.add_source(File::with_name(&config_path));
        }

        let settings = builder.build().context("Falha ao construir configuração")?;

        let host = settings
            .get_string("HOST")
            .unwrap_or_else(|_| default_host().to_string());

        let port = settings
            .get_int("PORT")
            .map(|value| value as u16)
            .unwrap_or_else(|_| default_port());

        let database_url = settings
            .get_string("DATABASE_URL")
            .or_else(|_| settings.get_string("POSTGRES_URL"))
            .context("Defina DATABASE_URL com a string de conexão PostgreSQL")?;

        let redis_url = settings
            .get_string("REDIS_URL")
            .context("Defina REDIS_URL com a string de conexão Redis")?;

        let jwt_secret = settings
            .get_string("JWT_SECRET")
            .unwrap_or_else(|_| default_jwt_secret().to_string());

        let jwt_expiration_hours = settings
            .get_int("JWT_EXPIRATION_HOURS")
            .map(|value| value as i64)
            .unwrap_or_else(|_| default_jwt_expiration_hours());

        let admin_username = settings
            .get_string("ADMIN_USERNAME")
            .unwrap_or_else(|_| default_admin_username().to_string());

        let password_hash = settings.get_string("ADMIN_PASSWORD_HASH").ok();
        let plain_password = settings.get_string("ADMIN_PASSWORD").ok();

        let admin_password_hash = resolve_password_hash(password_hash, plain_password.as_deref())?;

        let rate_limit_requests_per_minute = settings
            .get_int("RATE_LIMIT_REQUESTS_PER_MINUTE")
            .map(|value| value.max(1) as u32)
            .unwrap_or_else(|_| default_rate_limit_requests());

        Ok(Self {
            host,
            port,
            database_url,
            redis_url,
            jwt_secret,
            jwt_expiration_hours,
            admin_username,
            admin_password_hash,
            rate_limit_requests_per_minute,
        })
    }

    /// Endereço IP de binding.
    pub fn host(&self) -> &str {
        &self.host
    }

    /// Porta TCP de binding.
    pub fn port(&self) -> u16 {
        self.port
    }

    /// URL de conexão PostgreSQL.
    pub fn database_url(&self) -> &str {
        &self.database_url
    }

    /// URL de conexão Redis.
    pub fn redis_url(&self) -> &str {
        &self.redis_url
    }

    /// Segredo para assinatura de JWTs.
    pub fn jwt_secret(&self) -> &str {
        &self.jwt_secret
    }

    /// Janela de expiração em horas.
    pub fn jwt_expiration_hours(&self) -> i64 {
        self.jwt_expiration_hours
    }

    /// Usuário administrador padrão para autenticação administrativa.
    pub fn admin_username(&self) -> &str {
        &self.admin_username
    }

    /// Hash Argon2id da credencial administrativa.
    pub fn admin_password_hash(&self) -> &str {
        &self.admin_password_hash
    }

    /// Número máximo de requisições por IP por minuto.
    pub fn rate_limit_requests_per_minute(&self) -> u32 {
        self.rate_limit_requests_per_minute
    }

    /// Duração derivada da janela de expiração dos JWTs.
    pub fn jwt_ttl(&self) -> Duration {
        Duration::from_secs((self.jwt_expiration_hours * 3600) as u64)
    }
}

fn resolve_password_hash(
    hash_from_env: Option<String>,
    plain_password: Option<&str>,
) -> Result<String> {
    if let Some(hash) = hash_from_env {
        return Ok(hash);
    }

    if let Some(password) = plain_password {
        let salt = SaltString::generate(&mut OsRng);
        let hash = Argon2::default()
            .hash_password(password.as_bytes(), &salt)
            .map_err(|err| anyhow!("Falha ao derivar hash Argon2 da senha administrativa: {err}"))?
            .to_string();
        return Ok(hash);
    }

    // fallback deterministic for default credentials (user: admin, pass: test)
    let salt = SaltString::encode_b64(b"beagle-default-salt").expect("salt estático válido");
    let hash = Argon2::default()
        .hash_password(b"test", &salt)
        .expect("hash Argon2 determinístico")
        .to_string();
    Ok(hash)
}

const fn default_port() -> u16 {
    3000
}

fn default_host() -> &'static str {
    "0.0.0.0"
}

fn default_jwt_secret() -> &'static str {
    "development-secret-change-in-production"
}

const fn default_jwt_expiration_hours() -> i64 {
    24
}

fn default_admin_username() -> &'static str {
    "admin"
}

const fn default_rate_limit_requests() -> u32 {
    100
}
