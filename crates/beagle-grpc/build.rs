use std::path::Path;
use std::time::SystemTime;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let proto = Path::new("../../protos/beagle.proto");
    let proto_dir = Path::new("../../protos");
    let generated = Path::new("src/generated/beagle.v1.rs");

    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-changed={}", proto.display());

    let force_regen = std::env::var("BEAGLE_GRPC_REGENERATE")
        .ok()
        .is_some_and(|v| matches!(v.trim(), "1" | "true" | "yes" | "y"));

    let proto_is_newer = || -> bool {
        let Ok(proto_m) = proto.metadata() else {
            return false;
        };
        let Ok(gen_m) = generated.metadata() else {
            return true;
        };
        let Ok(proto_t) = proto_m.modified() else {
            return false;
        };
        let Ok(gen_t) = gen_m.modified() else {
            return true;
        };
        proto_t > gen_t
    };

    if force_regen || !generated.exists() || proto_is_newer() {
        let res = tonic_build::configure()
            .build_server(true)
            .build_client(true)
            // Keep generated sources checked-in for environments without protoc.
            .out_dir("src/generated")
            .compile_protos(&[proto], &[proto_dir]);

        if let Err(err) = res {
            let msg = err.to_string();
            let protoc_missing = msg.contains("Could not find `protoc`")
                || msg.contains("protoc")
                || msg.contains("protobuf-compiler");

            if protoc_missing && generated.exists() {
                println!(
                    "cargo:warning=beagle-grpc: protoc not available; using checked-in generated code at {} (set BEAGLE_GRPC_REGENERATE=1 to force regen when protoc is installed)",
                    generated.display()
                );
                return Ok(());
            }

            return Err(Box::new(err));
        }
    } else {
        // Ensure Cargo rebuilds if the checked-in generated file changes.
        println!("cargo:rerun-if-changed={}", generated.display());

        // Emit a warning if the proto appears newer, but regeneration is not requested.
        if let (Ok(proto_m), Ok(gen_m)) = (proto.metadata(), generated.metadata()) {
            let proto_t = proto_m.modified().unwrap_or(SystemTime::UNIX_EPOCH);
            let gen_t = gen_m.modified().unwrap_or(SystemTime::UNIX_EPOCH);
            if proto_t > gen_t {
                println!(
                    "cargo:warning=beagle-grpc: {} is newer than {}; set BEAGLE_GRPC_REGENERATE=1 to regenerate (requires protoc)",
                    proto.display(),
                    generated.display()
                );
            }
        }
    }

    Ok(())
}
