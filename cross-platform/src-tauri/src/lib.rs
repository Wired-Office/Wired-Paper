//! Wired Paper for Windows and Linux: the native side of the app.
//!
//! The editor runs in the webview; this file gives it file access, the
//! document passed on the command line, and a bridge to a local Ollama
//! server for writing suggestions. Ollama requests are only ever sent to this
//! computer, so text never leaves it.

use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::time::Duration;

use serde::Deserialize;
use tauri::ipc::{InvokeBody, Request, Response};

// MARK: - Files

#[tauri::command]
fn read_file(path: String) -> Result<Response, String> {
    fs::read(&path).map(Response::new).map_err(|e| describe(&path, e))
}

/// Writes the raw request body to the percent-encoded path in the `x-path`
/// header. Writes to a temporary file first so a failed save never leaves a
/// half-written document behind.
#[tauri::command]
fn write_file(request: Request<'_>) -> Result<(), String> {
    let InvokeBody::Raw(data) = request.body() else {
        return Err("Expected file contents.".into());
    };
    let encoded = request
        .headers()
        .get("x-path")
        .and_then(|value| value.to_str().ok())
        .ok_or("Missing file path.")?;
    let path = PathBuf::from(percent_decode(encoded).ok_or("Invalid file path.")?);
    write_atomically(&path, data).map_err(|e| describe(&path.to_string_lossy(), e))
}

fn write_atomically(path: &Path, data: &[u8]) -> std::io::Result<()> {
    let name = path.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
    let temp = path.with_file_name(format!(".{name}.wiredpaper-tmp"));
    {
        let mut file = fs::File::create(&temp)?;
        file.write_all(data)?;
        file.sync_all()?;
    }
    fs::rename(&temp, path).or_else(|error| {
        // Some network and synced folders refuse renames over existing files.
        let _ = fs::remove_file(&temp);
        if path.exists() {
            fs::write(path, data)
        } else {
            Err(error)
        }
    })
}

fn percent_decode(input: &str) -> Option<String> {
    let bytes = input.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' {
            let hex = std::str::from_utf8(bytes.get(i + 1..i + 3)?).ok()?;
            out.push(u8::from_str_radix(hex, 16).ok()?);
            i += 3;
        } else {
            out.push(bytes[i]);
            i += 1;
        }
    }
    String::from_utf8(out).ok()
}

fn describe(path: &str, error: std::io::Error) -> String {
    let name = Path::new(path).file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_else(|| path.to_string());
    match error.kind() {
        std::io::ErrorKind::NotFound => format!("“{name}” couldn't be found."),
        std::io::ErrorKind::PermissionDenied => format!("You don't have permission to access “{name}”."),
        _ => format!("{error} ({name})"),
    }
}

/// The document to open at launch, e.g. after double-clicking a .paper file.
#[tauri::command]
fn initial_file() -> Option<String> {
    std::env::args()
        .skip(1)
        .find(|arg| !arg.starts_with('-') && Path::new(arg).is_file())
}

/// How this copy was installed, so updates offer the right download.
#[tauri::command]
fn install_kind() -> &'static str {
    if cfg!(target_os = "windows") {
        "windows"
    } else if std::env::var_os("APPIMAGE").is_some() {
        "appimage"
    } else if cfg!(target_os = "linux") {
        "deb"
    } else {
        "other"
    }
}

// MARK: - Local AI (Ollama)

/// Only addresses on this computer are allowed, so suggestions stay local.
fn local_base(base_url: &str) -> Result<String, String> {
    let url = base_url.trim().trim_end_matches('/');
    let rest = url.strip_prefix("http://").ok_or("Ollama must be reached over http:// on this computer.")?;
    let host = rest.split(['/', '?']).next().unwrap_or("");
    let host_name = if host.starts_with('[') {
        host.split(']').next().map(|h| format!("{h}]")).unwrap_or_default()
    } else {
        host.split(':').next().unwrap_or("").to_string()
    };
    match host_name.as_str() {
        "localhost" | "127.0.0.1" | "[::1]" => Ok(url.to_string()),
        _ => Err("Writing suggestions only use a model running on this computer.".into()),
    }
}

fn client(timeout: Duration) -> Result<reqwest::Client, String> {
    reqwest::Client::builder().timeout(timeout).build().map_err(|e| e.to_string())
}

#[derive(Deserialize)]
struct Tags {
    #[serde(default)]
    models: Vec<Tag>,
}

#[derive(Deserialize)]
struct Tag {
    name: String,
}

#[tauri::command]
async fn ollama_models(base_url: String) -> Result<Vec<String>, String> {
    let base = local_base(&base_url)?;
    let response = client(Duration::from_secs(3))?
        .get(format!("{base}/api/tags"))
        .send()
        .await
        .map_err(|_| "Ollama isn't running.".to_string())?;
    let tags: Tags = response.error_for_status().map_err(|e| e.to_string())?.json().await.map_err(|e| e.to_string())?;
    Ok(tags.models.into_iter().map(|m| m.name).collect())
}

#[derive(Deserialize)]
struct Generated {
    #[serde(default)]
    response: String,
}

#[tauri::command]
async fn ollama_generate(base_url: String, model: String, system: String, prompt: String) -> Result<String, String> {
    let base = local_base(&base_url)?;
    let body = serde_json::json!({
        "model": model,
        "system": system,
        "prompt": prompt,
        "stream": false,
        "keep_alive": "10m",
        "options": { "temperature": 0.2, "num_predict": 40 }
    });
    let response = client(Duration::from_secs(30))?
        .post(format!("{base}/api/generate"))
        .json(&body)
        .send()
        .await
        .map_err(|e| e.to_string())?;
    let generated: Generated = response.error_for_status().map_err(|e| e.to_string())?.json().await.map_err(|e| e.to_string())?;
    Ok(generated.response)
}

// MARK: - App

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_opener::init())
        .invoke_handler(tauri::generate_handler![
            read_file,
            write_file,
            initial_file,
            install_kind,
            ollama_models,
            ollama_generate
        ])
        .run(tauri::generate_context!())
        .expect("error while running Wired Paper");
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_local_ollama_addresses_are_allowed() {
        assert!(local_base("http://127.0.0.1:11434").is_ok());
        assert!(local_base("http://localhost:11434/").is_ok());
        assert!(local_base("http://[::1]:11434").is_ok());
        assert!(local_base("http://example.com:11434").is_err());
        assert!(local_base("http://localhost.evil.com").is_err());
        assert!(local_base("http://127.0.0.1.nip.io").is_err());
        assert!(local_base("https://localhost:11434").is_err());
    }

    #[test]
    fn decodes_percent_encoded_paths() {
        assert_eq!(percent_decode("C%3A%5CUsers%5Cj%C3%BCrgen%5CBrief.paper").unwrap(), "C:\\Users\\jürgen\\Brief.paper");
        assert!(percent_decode("%zz").is_none());
    }

    #[test]
    fn writes_atomically() {
        let dir = std::env::temp_dir().join(format!("wp-test-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join("Döc.paper");
        write_atomically(&path, b"one").unwrap();
        write_atomically(&path, b"two").unwrap();
        assert_eq!(fs::read(&path).unwrap(), b"two");
        assert_eq!(fs::read_dir(&dir).unwrap().count(), 1);
        fs::remove_dir_all(&dir).unwrap();
    }
}
