use rocket::fs::{relative, FileServer};
use rocket::serde::{Deserialize, Serialize};
use rocket::{launch, post, routes};
use std::process::Stdio;
use tokio::process::Command;

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
    let output = match Command::new("sh")
        .arg("-c")
        .arg(&req.command)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()
        .await
    {
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

#[launch]
fn rocket() -> _ {
    let config = rocket::config::Config {
        address: std::net::IpAddr::V4(std::net::Ipv4Addr::new(0, 0, 0, 0)),
        ..rocket::config::Config::default()
    };

    rocket::build()
        .configure(config)
        .mount("/", FileServer::from(relative!("./www")).rank(1))
        .mount("/", routes![execute_command])
}
