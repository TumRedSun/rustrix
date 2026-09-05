// build.rs
// Minimal build script. qmetaobject handles its own Qt discovery via pkg-config
// and QMAKE. We expose a few extra env knobs for the user.

fn qmake_query(prop: &str) -> String {
    let qmake = std::env::var("QMAKE").unwrap_or_default();
    let candidates: Vec<String> = if qmake.is_empty() {
        vec!["qmake6".into(), "qmake-qt6".into(), "qmake".into()]
    } else {
        vec![qmake]
    };
    for q in candidates {
        if let Ok(out) = std::process::Command::new(&q).args(["-query", prop]).output() {
            if out.status.success() {
                return String::from_utf8_lossy(&out.stdout).trim().to_string();
            }
        }
    }
    String::new()
}

fn main() {
    // Allow the user to point to a custom qmake via QMAKE env var.
    if std::env::var("QMAKE").is_err() {
        // Try common Linux qmake binaries.
        for candidate in ["qmake6", "qmake-qt6", "qmake"] {
            if which::which(candidate).is_ok() {
                println!("cargo:rustc-env=QMAKE={}", candidate);
                break;
            }
        }
    }

    // The cpp! fragments in src/main.rs (window icon) are compiled with the
    // cpp crate's build helper and need the Qt include paths. Qt is required
    // by qmetaobject anyway, so fail loudly instead of producing a confusing
    // link error later.
    let qt_headers = qmake_query("QT_INSTALL_HEADERS");
    let qt_libs = qmake_query("QT_INSTALL_LIBS");
    if qt_headers.is_empty() {
        panic!(
            "Could not locate Qt 6 (no working qmake6/qmake found). \
             Install the Qt 6 development packages or set QMAKE=/path/to/qmake6"
        );
    }
    cpp_build::Config::new()
        .include(&qt_headers)
        .flag("-std=c++17")
        .build("src/main.rs");
    println!("cargo:rustc-link-search=native={}", qt_libs);
    println!("cargo:rustc-link-lib=dylib=Qt6Core");
    println!("cargo:rustc-link-lib=dylib=Qt6Gui");

    println!("cargo:rerun-if-changed=qml");
    println!("cargo:rerun-if-changed=assets");
    println!("cargo:rerun-if-changed=Cargo.toml");
}

// Minimal which() helper to avoid an extra dependency.
mod which {
    use std::path::PathBuf;
    pub fn which(cmd: &str) -> Result<PathBuf, ()> {
        if let Ok(path) = std::env::var("PATH") {
            for dir in path.split(':') {
                let p: PathBuf = std::path::Path::new(dir).join(cmd);
                if p.is_file() {
                    return Ok(p);
                }
            }
        }
        Err(())
    }
}
