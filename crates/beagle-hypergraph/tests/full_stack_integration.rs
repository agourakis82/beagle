use beagle_db::Migrator;
use beagle_hypergraph::{
    models::{ContentType, Node},
    storage::{CachedPostgresStorage, PostgresStorage, StorageRepository},
};
use testcontainers::{clients, core::WaitFor, GenericImage};
use testcontainers_modules::redis::Redis;

fn create_test_node() -> Node {
    Node::builder()
        .content("Hipergrafo integrado em contêiner")
        .content_type(ContentType::Thought)
        .device_id("integration-suite")
        .build()
        .expect("builder deve produzir nó válido")
}

#[tokio::test]
async fn test_full_stack_integration() {
    let docker = clients::Cli::default();

    let postgres_image = GenericImage::new("pgvector/pgvector", "pg16")
        .with_env_var("POSTGRES_DB", "beagle_fullstack")
        .with_env_var("POSTGRES_USER", "postgres")
        .with_env_var("POSTGRES_PASSWORD", "postgres")
        .with_wait_for(WaitFor::message_on_stderr(
            "database system is ready to accept connections",
        ));

    let redis_image = Redis::default();

    let postgres_container = docker.run(postgres_image);
    let redis_container = docker.run(redis_image);

    let db_url = format!(
        "postgres://postgres:postgres@127.0.0.1:{}/beagle_fullstack",
        postgres_container.get_host_port_ipv4(5432)
    );
    let redis_url = format!(
        "redis://127.0.0.1:{}",
        redis_container.get_host_port_ipv4(6379)
    );

    let storage = PostgresStorage::new(&db_url)
        .await
        .expect("conexão PostgreSQL deve ser estabelecida");

    Migrator::new(storage.pool().clone())
        .run_migrations()
        .await
        .expect("migrações devem ser aplicadas");

    let baseline_node = create_test_node();
    let persisted = storage
        .create_node(baseline_node.clone())
        .await
        .expect("criação no Postgres deve suceder");
    let fetched = storage
        .get_node(persisted.id)
        .await
        .expect("consulta direta deve retornar nó");

    assert_eq!(baseline_node.content, fetched.content);
    assert_eq!(persisted.device_id, fetched.device_id);

    let cached_storage = CachedPostgresStorage::new(&db_url, &redis_url)
        .await
        .expect("instância cacheada deve inicializar");

    cached_storage
        .cache()
        .flush_all()
        .await
        .expect("flush do Redis deve limpar estado prévio");

    let cached_node = create_test_node();
    let cached_persisted = cached_storage
        .create_node(cached_node.clone())
        .await
        .expect("criação via camada cacheada deve suceder");

    let first_read = cached_storage
        .get_node(cached_persisted.id)
        .await
        .expect("primeira leitura deve retornar nó");
    let second_read = cached_storage
        .get_node(cached_persisted.id)
        .await
        .expect("segunda leitura deve reutilizar cache");

    assert_eq!(first_read.id, second_read.id);
    assert_eq!(first_read.content, cached_node.content);

    let stats = cached_storage
        .cache_stats()
        .await
        .expect("estatísticas do cache devem estar acessíveis");
    assert!(
        stats.hits >= 1,
        "esperava pelo menos um cache hit, stats: {:?}",
        stats
    );

    cached_storage
        .delete_node(cached_persisted.id)
        .await
        .expect("remoção final deve ocorrer sem erros");
    storage
        .delete_node(persisted.id)
        .await
        .expect("limpeza do nó baseline deve suceder");
}
