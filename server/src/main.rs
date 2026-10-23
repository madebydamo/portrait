use reqwest::Client;
use rocket::fs::FileServer;
use rocket::serde::{Deserialize, Serialize};
use rocket::{get, launch, post, routes};
use std::fs::File;
use std::io::{self, Read};
use std::net::IpAddr;
use std::os::unix::io::FromRawFd;
use std::process::Stdio;
use std::time::Duration;
use tokio::io::AsyncReadExt;
use tokio::task;
use tokio::time::timeout;

#[derive(Deserialize)]
#[serde(crate = "rocket::serde")]
struct CommandRequest {
    command: String,
    width: Option<i32>,
}

#[derive(Serialize)]
#[serde(crate = "rocket::serde")]
struct CommandResponse {
    stdout: String,
    stderr: String,
    status: i32,
}

// Master, plus the slave as the guest's stdout. None means use a pipe.
fn open_guest_stdout(columns: Option<i32>) -> Option<(File, File)> {
    let columns = match columns {
        Some(width) if width > 0 => u16::try_from(width).unwrap_or(u16::MAX),
        _ => 80,
    };
    unsafe {
        let master_fd = libc::posix_openpt(libc::O_RDWR | libc::O_NOCTTY | libc::O_CLOEXEC);
        if master_fd < 0 {
            return None;
        }
        if libc::grantpt(master_fd) != 0 || libc::unlockpt(master_fd) != 0 {
            libc::close(master_fd);
            return None;
        }
        let mut name = [0i8; 128];
        if libc::ptsname_r(master_fd, name.as_mut_ptr(), name.len()) != 0 {
            libc::close(master_fd);
            return None;
        }
        let slave_fd = libc::open(name.as_ptr(), libc::O_RDWR | libc::O_NOCTTY | libc::O_CLOEXEC);
        if slave_fd < 0 {
            libc::close(master_fd);
            return None;
        }
        let mut termios = std::mem::zeroed();
        if libc::tcgetattr(slave_fd, &mut termios) != 0 {
            libc::close(master_fd);
            libc::close(slave_fd);
            return None;
        }
        libc::cfmakeraw(&mut termios);
        if libc::tcsetattr(slave_fd, libc::TCSANOW, &termios) != 0 {
            libc::close(master_fd);
            libc::close(slave_fd);
            return None;
        }
        let mut size = libc::winsize {
            ws_row: 24,
            ws_col: columns,
            ws_xpixel: 0,
            ws_ypixel: 0,
        };
        libc::ioctl(slave_fd, libc::TIOCSWINSZ, &mut size);
        Some((
            File::from_raw_fd(master_fd),
            File::from_raw_fd(slave_fd),
        ))
    }
}

// A pty master returns EIO once the slave side closes, after the buffered bytes.
fn read_pty_master(mut master: File) -> Vec<u8> {
    let mut buf = Vec::new();
    let mut tmp = [0u8; 8192];
    loop {
        match master.read(&mut tmp) {
            Ok(0) => break,
            Ok(n) => buf.extend_from_slice(&tmp[..n]),
            Err(err) if err.raw_os_error() == Some(libc::EIO) => break,
            Err(err) if err.kind() == io::ErrorKind::Interrupted => continue,
            Err(_) => break,
        }
    }
    buf
}

#[post("/execute", data = "<req>")]
async fn execute_command(
    ip: Option<IpAddr>,
    req: rocket::serde::json::Json<CommandRequest>,
) -> rocket::serde::json::Json<CommandResponse> {
    // ip comes from X-Real-IP (set by SWAG), else the peer address.
    // {:?} escapes newlines so a command cannot forge extra log lines.
    let ip = ip.map_or_else(|| "-".to_string(), |ip| ip.to_string());
    println!("portrait-exec: ip={} cmd={:?}", ip, req.command);
    if req.command.starts_with("message ") {
        let message = req.command.strip_prefix("message ").unwrap_or("").trim();
        if message.is_empty() {
            return rocket::serde::json::Json(CommandResponse {
                stdout: "".to_string(),
                stderr: "Error: No message provided".to_string(),
                status: 1,
            });
        }
        let token = match std::env::var("TELEGRAM_BOT_TOKEN") {
            Ok(t) => t,
            Err(_) => {
                return rocket::serde::json::Json(CommandResponse {
                    stdout: "".to_string(),
                    stderr: "Error: TELEGRAM_BOT_TOKEN not set".to_string(),
                    status: 1,
                });
            }
        };
        let chat_id = match std::env::var("TELEGRAM_CHAT_ID") {
            Ok(c) => c,
            Err(_) => {
                return rocket::serde::json::Json(CommandResponse {
                    stdout: "".to_string(),
                    stderr: "Error: TELEGRAM_CHAT_ID not set".to_string(),
                    status: 1,
                });
            }
        };
        let client = Client::new();
        let url = format!("https://api.telegram.org/bot{}/sendMessage", token);
        let response = client
            .post(&url)
            .json(&serde_json::json!({
                "chat_id": chat_id,
                "text": message
            }))
            .send()
            .await;
        match response {
            Ok(resp) if resp.status().is_success() => {
                return rocket::serde::json::Json(CommandResponse {
                    stdout: "Message sent successfully".to_string(),
                    stderr: "".to_string(),
                    status: 0,
                });
            }
            Ok(resp) => {
                let status = resp.status();
                let body = resp
                    .text()
                    .await
                    .unwrap_or_else(|_| "Failed to read response body".to_string());
                return rocket::serde::json::Json(CommandResponse {
                    stdout: "".to_string(),
                    stderr: format!("Error: Telegram API returned {} - {}", status, body),
                    status: 1,
                });
            }
            Err(e) => {
                return rocket::serde::json::Json(CommandResponse {
                    stdout: "".to_string(),
                    stderr: format!("Error: {}", e),
                    status: 1,
                });
            }
        }
    }

    let mut cmd = tokio::process::Command::new("prlimit");
    cmd.arg("--cpu=5");
    // 128 MiB virtual address space. Ruby lolcat fails under 50 MiB, and
    // the failure point moves around 72-80 MiB depending on mapping layout.
    cmd.arg("--as=134217728");
    // Real uid 999 so iptables owner-match applies. Root + bwrap --uid remaps skuid to 0.
    // --unshare-user here maps 999 -> 999; it does not remap skuid to 0.
    cmd.arg("setpriv");
    cmd.arg("--reuid=999");
    cmd.arg("--regid=999");
    cmd.arg("--clear-groups");
    cmd.arg("--nnp");
    cmd.arg("--inh-caps=-all");
    cmd.arg("--bounding-set=-all");
    cmd.arg("--");
    cmd.arg("bwrap");
    cmd.arg("--unshare-user");
    cmd.arg("--ro-bind").arg("/").arg("/");
    cmd.arg("--dev-bind").arg("/dev").arg("/dev");
    cmd.arg("--unshare-pid");
    cmd.arg("--bind").arg("/proc").arg("/proc");
    // Public DNS only — no Docker/gluetun names for container hosts.
    // Installed at image build from scripts/resolv.sandbox.conf.
    cmd.arg("--ro-bind")
        .arg("/etc/portrait/resolv.sandbox.conf")
        .arg("/etc/resolv.conf");
    cmd.arg("--new-session");
    cmd.arg("--die-with-parent");
    cmd.arg("--clearenv");
    cmd.arg("--setenv")
        .arg("PATH")
        .arg("/usr/games:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin");
    cmd.arg("--chdir").arg("/home/damo");
    cmd.arg("--setenv").arg("HOME").arg("/home/damo");
    cmd.arg("--setenv").arg("USER").arg("damo");
    if let Some(width) = req.width {
        cmd.arg("--setenv").arg("COLUMNS").arg(width.to_string());
    }
    cmd.arg("--");
    // script(1) opens its own pty inside the guest. As uid 999 that output
    // never reached us. stdbuf leaves the guest on the fds attached below.
    cmd.arg("stdbuf");
    cmd.arg("-o0");
    cmd.arg("-e0");
    cmd.arg("bash");
    cmd.arg("-c");
    cmd.arg(&req.command);
    // A pipe makes lolcat copy stdin unchanged. A pty makes stdout a tty so it
    // colorizes. stderr stays a pipe so success can still drop curl's meter.
    let pty_master = match open_guest_stdout(req.width) {
        Some((master, slave)) => {
            cmd.stdout(Stdio::from(slave));
            Some(master)
        }
        None => {
            eprintln!("portrait-exec: pty unavailable, stdout is a pipe");
            cmd.stdout(Stdio::piped());
            None
        }
    };
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

    let mut stderr_reader = child.stderr.take().expect("stderr piped");

    let stdout_task = if let Some(master) = pty_master {
        task::spawn_blocking(move || String::from_utf8_lossy(&read_pty_master(master)).into_owned())
    } else {
        let mut stdout_reader = child.stdout.take().expect("stdout piped");
        task::spawn(async move {
            let mut buf = Vec::new();
            let _ = stdout_reader.read_to_end(&mut buf).await;
            String::from_utf8_lossy(&buf).to_string()
        })
    };

    let stderr_task = task::spawn(async move {
        let mut buf = Vec::new();
        let _ = stderr_reader.read_to_end(&mut buf).await;
        String::from_utf8_lossy(&buf).to_string()
    });

    let wait_result = timeout(Duration::from_secs(10), child.wait()).await;

    let (stdout, mut stderr, status) = match wait_result {
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

    // Curl's progress meter and similar noise go to stderr even on success.
    // The page renders stderr in red, so drop it when the command worked.
    if status == 0 {
        stderr.clear();
    }

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

#[cfg(test)]
mod tests {
    use super::{open_guest_stdout, read_pty_master};
    use std::io::Write;
    use std::process::{Command, Stdio};
    use std::thread;

    #[test]
    fn guest_stdout_pty_is_a_raw_tty() {
        let Some((master, slave)) = open_guest_stdout(Some(40)) else {
            return;
        };
        let mut child = Command::new("sh")
            .args([
                "-c",
                "if [ -t 1 ]; then printf 'tty=True\\n'; else printf 'tty=False\\n'; fi",
            ])
            .stdin(Stdio::null())
            .stdout(Stdio::from(slave))
            .stderr(Stdio::null())
            .spawn()
            .expect("spawn sh");
        let reader = thread::spawn(move || read_pty_master(master));
        let status = child.wait().expect("wait");
        let buf = reader.join().expect("reader");
        assert!(status.success());
        assert_eq!(String::from_utf8_lossy(&buf), "tty=True\n");
    }

    #[test]
    fn lolcat_colors_a_pty_and_not_a_pipe() {
        let Ok(lolcat) = std::env::var("LOLCAT") else {
            return;
        };
        let Some((master, slave)) = open_guest_stdout(Some(80)) else {
            return;
        };
        let mut child = Command::new(&lolcat)
            .stdin(Stdio::piped())
            .stdout(Stdio::from(slave))
            .stderr(Stdio::null())
            .env_clear()
            .env("PATH", "/usr/bin:/bin")
            .env("HOME", "/tmp")
            .spawn()
            .expect("spawn lolcat");
        child
            .stdin
            .take()
            .expect("stdin")
            .write_all(b"Hello\n")
            .expect("write");
        let reader = thread::spawn(move || read_pty_master(master));
        let status = child.wait().expect("wait");
        let colored = reader.join().expect("reader");
        assert!(status.success(), "lolcat on a pty failed");
        assert!(
            colored.windows(4).any(|w| w == b"38;5"),
            "pty lolcat produced no 256-color codes: {colored:?}"
        );
        assert!(!colored.contains(&b'\r'));

        let mut plain = Command::new(&lolcat)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .env_clear()
            .env("PATH", "/usr/bin:/bin")
            .env("HOME", "/tmp")
            .spawn()
            .expect("spawn plain lolcat");
        plain
            .stdin
            .take()
            .expect("stdin")
            .write_all(b"Hello\n")
            .expect("write");
        let plain_out = plain.wait_with_output().expect("wait plain");
        assert!(plain_out.status.success());
        assert_eq!(plain_out.stdout, b"Hello\n");
    }
}

#[launch]
fn rocket() -> _ {
    rocket::build()
        .configure(rocket::config::Config::figment())
        .mount("/", FileServer::from("./www").rank(1))
        .mount("/", routes![execute_command, get_commands])
}
