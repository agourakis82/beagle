use beagle_personality::PersonalityEngine;

fn main() {
    tracing_subscriber::fmt()
        .with_max_level(tracing::Level::INFO)
        .init();

    println!("╔══════════════════════════════════════════════╗");
    println!("║  Beagle Personality Engine - Demo           ║");
    println!("╚══════════════════════════════════════════════╝\n");

    let engine = PersonalityEngine::new();

    println!("📚 Available domains:");
    for domain in engine.available_domains() {
        if let Some(info) = engine.profile_info(domain) {
            println!("  • {}", info);
        }
    }
    println!();

    let test_cases = vec![
        (
            "Calcule o clearance renal e a meia-vida deste antibiótico PBPK",
            "PBPK",
        ),
        (
            "Paciente com hipertensão e diabetes tipo 2 apresenta dispneia aos esforços",
            "ClinicalMedicine",
        ),
        ("Iniciar fluoxetina 20mg para depressão maior", "Psychiatry"),
        (
            "Compare risperidona e olanzapina na esquizofrenia",
            "Psychiatry",
        ),
        (
            "Explique a fenomenologia da consciência sob perspectiva fenomenológica husserliana",
            "Philosophy",
        ),
        ("Refatore este código Rust usando traits", "BeagleEngine"),
        (
            "Analise a harmonia tonal e modulação desta progressão em Dó maior",
            "Music",
        ),
        ("Qual a capital da França?", "General"),
    ];

    println!("╔══════════════════════════════════════════════╗");
    println!("║  Domain Detection Tests                     ║");
    println!("╚══════════════════════════════════════════════╝\n");

    for (i, (query, expected)) in test_cases.iter().enumerate() {
        println!("Test {}/{}:", i + 1, test_cases.len());
        println!("📝 Query: {}", query);

        let domain = engine.detect_domain(query);
        let domains_multi = engine.detect_domains(query, 3);

        println!("🎯 Detected: {:?}", domain);
        println!("📊 Scores: {:?}", domains_multi);

        let match_symbol = if format!("{:?}", domain) == *expected {
            "✅"
        } else {
            "⚠️"
        };
        println!("{} Expected domain: {}\n", match_symbol, expected);
    }

    println!("╔══════════════════════════════════════════════╗");
    println!("║  System Prompt Examples                     ║");
    println!("╚══════════════════════════════════════════════╝\n");

    let demo_queries = vec![
        "Calcule a farmacocinética (clearance e meia-vida) deste antibiótico",
        "Paciente com hipertensão resistente e dispneia aos esforços",
        "Depressão maior com ansiedade generalizada",
    ];

    for query in demo_queries {
        let domain = engine.detect_domain(query);
        let prompt = engine.system_prompt_for(query);

        println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
        println!("Query: {}", query);
        println!("Domain: {:?}", domain);
        println!("\nSystem Prompt Preview (first 300 chars):");
        println!("{}", prompt.chars().take(300).collect::<String>());
        println!("...\n");
    }

    println!("╔══════════════════════════════════════════════╗");
    println!("║  ✅ Demo Complete                            ║");
    println!("╚══════════════════════════════════════════════╝");
}
