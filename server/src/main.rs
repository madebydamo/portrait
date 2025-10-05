use rocket::fs::{relative, FileServer};
use rocket::serde::{Deserialize, Serialize};
use rocket::{get, launch, post, routes};
use std::process::Stdio;

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
    cmd.arg("timeout");
    cmd.arg("5s");
    cmd.arg("bwrap");
    cmd.arg("--unshare-user");
    cmd.arg("--ro-bind").arg("/").arg("/");
    cmd.arg("--dev-bind").arg("/dev").arg("/dev");
    cmd.arg("--proc").arg("/proc");
    cmd.arg("--new-session");
    cmd.arg("--die-with-parent");
    cmd.arg("--uid").arg("999");
    cmd.arg("--gid").arg("999");
    cmd.arg("--chdir").arg("/home/damo");
    cmd.arg("--");
    cmd.arg("/bin/sh");
    cmd.arg("-c");
    cmd.arg(&req.command);

    cmd.stdout(Stdio::piped());
    cmd.stderr(Stdio::piped());

    let output = match cmd.output().await {
        Ok(o) => o,
        Err(_) => {
            return rocket::serde::json::Json(CommandResponse {
                stdout: "".to_string(),
                stderr: "Failed to execute command".to_string(),
                status: -1,
            });
        }
    };

    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();
    let status = output.status.code().unwrap_or(-1);

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
    let config = rocket::config::Config {
        address: std::net::IpAddr::V4(std::net::Ipv4Addr::new(0, 0, 0, 0)),
        ..rocket::config::Config::default()
    };

    rocket::build()
        .configure(config)
        .mount("/", FileServer::from(relative!("./www")).rank(1))
        .mount("/", routes![execute_command, get_commands])
}
