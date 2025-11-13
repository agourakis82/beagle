use crate::{domain::Domain, profile::Profile};
use once_cell::sync::Lazy;
use std::collections::HashMap;
use std::path::PathBuf;
use tracing::{debug, warn};

/// Loader de profiles com cache em memória
pub struct ProfileLoader {
    profiles: HashMap<Domain, Profile>,
}

impl ProfileLoader {
    /// Carrega todos os profiles disponíveis a partir de um diretório
    pub fn new(profiles_dir: Option<PathBuf>) -> Self {
        let dir = profiles_dir
            .unwrap_or_else(|| PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("profiles"));

        debug!("Carregando profiles a partir de {:?}", dir);

        let mut profiles = HashMap::new();

        for domain in Domain::specialized() {
            let filename = domain.profile_file();
            let path = dir.join(filename);

            match std::fs::read_to_string(&path) {
                Ok(content) => match Profile::from_toml(&content) {
                    Ok(profile) => {
                        debug!("✅ Profile carregado: {} ({})", domain, filename);
                        profiles.insert(domain, profile);
                    }
                    Err(e) => {
                        warn!("⚠️ Falha ao fazer parse de {}: {}", filename, e);
                    }
                },
                Err(e) => {
                    warn!("⚠️ Falha ao ler {}: {}", filename, e);
                }
            }
        }

        // Sempre tenta carregar o fallback General
        let general_path = dir.join("general.toml");
        match std::fs::read_to_string(&general_path) {
            Ok(content) => {
                if let Ok(profile) = Profile::from_toml(&content) {
                    debug!("✅ Profile fallback carregado: General");
                    profiles.insert(Domain::General, profile);
                }
            }
            Err(e) => warn!("⚠️ Falha ao carregar general.toml: {}", e),
        }

        Self { profiles }
    }

    /// Obtém profile para um domínio, com fallback para General
    pub fn get(&self, domain: Domain) -> Option<&Profile> {
        self.profiles
            .get(&domain)
            .or_else(|| self.profiles.get(&Domain::General))
    }

    /// Verifica se existe profile carregado para o domínio
    pub fn has(&self, domain: Domain) -> bool {
        self.profiles.contains_key(&domain)
    }

    /// Lista domínios carregados
    pub fn loaded_domains(&self) -> Vec<Domain> {
        self.profiles.keys().copied().collect()
    }
}

/// Loader global (lazy)
static GLOBAL_LOADER: Lazy<ProfileLoader> = Lazy::new(|| ProfileLoader::new(None));

/// Acesso ao loader global
pub fn global_loader() -> &'static ProfileLoader {
    &GLOBAL_LOADER
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_load_profiles() {
        let loader = ProfileLoader::new(None);

        assert!(loader.has(Domain::General));

        if let Some(profile) = loader.get(Domain::PBPK) {
            assert_eq!(profile.profile.domain, "PBPK");
        }
    }
}
