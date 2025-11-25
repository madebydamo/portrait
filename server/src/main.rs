use rocket::fs::{relative, FileServer};
use rocket::serde::{Deserialize, Serialize};
use rocket::{get, launch, post, routes};
use std::process::Stdio;
use std::time::Duration;
use tokio::io::AsyncReadExt;
use tokio::task;
use tokio::time::timeout;

#[derive(Deserialize)]
#[serde(crate = "rocket::serde")]
struct CommandRequest {
    command: String,
}

#[derive(Serialize)]
#[serde(crate = "rocket::serde")]
struct CommandResponse {
    stdout: String,
    stderr: String,
    status: i32,
}

#[post("/execute", data = "<req>")]
async fn execute_command(
    req: rocket::serde::json::Json<CommandRequest>,
) -> rocket::serde::json::Json<CommandResponse> {
    let mut cmd = tokio::process::Command::new("prlimit");
    cmd.arg("--cpu=5");
    cmd.arg("--as=100000000");
    cmd.arg("bwrap");
    cmd.arg("--unshare-user");
    cmd.arg("--ro-bind").arg("/").arg("/");
    cmd.arg("--dev-bind").arg("/dev").arg("/dev");
    cmd.arg("--unshare-pid");
    cmd.arg("--bind").arg("/proc").arg("/proc");
    cmd.arg("--new-session");
    cmd.arg("--die-with-parent");
    cmd.arg("--uid").arg("999");
    cmd.arg("--gid").arg("999");
    cmd.arg("--chdir").arg("/home/damo");
    cmd.arg("--setenv").arg("HOME").arg("/home/damo");
    cmd.arg("--setenv").arg("USER").arg("damo");
    cmd.arg("--");
    cmd.arg("script");
    cmd.arg("-q");
    cmd.arg("-c");
    cmd.arg(format!("stdbuf -o0 bash -c \"{}\"", &req.command));
    cmd.arg("/dev/null");
    cmd.stdout(Stdio::piped());
    cmd.stderr(Stdio::piped());

    let mut child = match cmd.spawn() {
        Ok(c) => c,
        Err(_) => {
            return rocket::serde::json::Json(CommandResponse {
                stdout: "".to_string(),
                stderr: "Failed to spawn command".to_string(),
                status: -1,
            });
        }
    };

    let mut stdout_reader = child.stdout.take().expect("stdout piped");
    let mut stderr_reader = child.stderr.take().expect("stderr piped");

    let stdout_task = task::spawn(async move {
        let mut buf = Vec::new();
        let _ = stdout_reader.read_to_end(&mut buf).await;
        String::from_utf8_lossy(&buf).to_string()
    });

    let stderr_task = task::spawn(async move {
        let mut buf = Vec::new();
        let _ = stderr_reader.read_to_end(&mut buf).await;
        String::from_utf8_lossy(&buf).to_string()
    });

    let wait_result = timeout(Duration::from_secs(5), child.wait()).await;

    let (stdout, stderr, status) = match wait_result {
        Ok(Ok(exit_status)) => (
            stdout_task.await.unwrap_or_default(),
            stderr_task.await.unwrap_or_default(),
            exit_status.code().unwrap_or(-1),
        ),
        Ok(Err(_)) | Err(_) => {
            let _ = child.kill().await;
            let _ = child.wait().await;
            stdout_task.abort();
            stderr_task.abort();
            ("".to_string(), "Command timed out".to_string(), -1)
        }
    };

    rocket::serde::json::Json(CommandResponse {
        stdout,
        stderr,
        status,
    })
}

#[get("/commands")]
fn get_commands() -> rocket::serde::json::Json<Vec<String>> {
    let mut commands = Vec::new();
    if let Ok(entries) = std::fs::read_dir("./www/commands") {
        for entry in entries {
            if let Ok(entry) = entry {
                if let Some(filename) = entry.file_name().to_str() {
                    if filename.ends_with(".html") {
                        let command = filename.trim_end_matches(".html").to_string();
                        commands.push(command);
                    }
                }
            }
        }
    }
    rocket::serde::json::Json(commands)
}

#[launch]
fn rocket() -> _ {
    rocket::build()
        .configure(rocket::config::Config::figment())
        .mount("/", FileServer::from(relative!("./www")).rank(1))
        .mount("/", routes![execute_command, get_commands])
}
