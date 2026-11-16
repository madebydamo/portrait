mod limits;
mod sandbox_fw;
mod telemetry;

use limits::{env_num, DailyCap, RateLimiter};
use rocket::data::{Limits, ToByteUnit};
use rocket::fairing::{Fairing, Info, Kind};
use rocket::fs::FileServer;
use rocket::http::{Method, Status};
use rocket::serde::json::Json;
use rocket::serde::{Deserialize, Serialize};
use rocket::{get, post, routes, Request, Response, State};
use sandbox_fw::SandboxFw;
use serde_json::json;
use std::collections::HashSet;
use std::fs::File;
use std::io::{self, Read};
use std::net::IpAddr;
use std::os::unix::io::FromRawFd;
use std::process::Stdio;
use std::sync::Arc;
use std::time::{Duration, Instant};
use telemetry::METRICS;
use tokio::io::AsyncReadExt;
use tokio::sync::Semaphore;
use tokio::task;

/// Longest command (or message) accepted, in bytes.
const MAX_COMMAND_BYTES: usize = 4000;
/// Wall-clock limit of one sandbox.
const EXEC_TIMEOUT: Duration = Duration::from_secs(10);

/// Top-level commands that get their own `command` label in
/// `portrait_exec_total`; everything else counts as "other". Fixed, so the
/// label stays small whatever visitors type.
const KNOWN_COMMANDS: &[&str] = &[
    "awk", "base64", "bash", "cal", "cat", "cd", "chmod", "clear", "compgen", "cowsay", "cowthink",
    "cp", "curl", "cut", "date", "df", "diff", "dig", "du", "echo", "env", "exit", "figlet",
    "find", "fortune", "free", "grep", "gzip", "head", "help", "history", "hostname", "id", "kill",
    "less", "lolcat", "ls", "man", "mkdir", "more", "mv", "nano", "nc", "neofetch", "nslookup",
    "perl", "ping", "printf", "ps", "pwd", "python", "python3", "rev", "rm", "sed", "seq", "sh",
    "sl", "sleep", "sort", "ssh", "su", "sudo", "tail", "tar", "tee", "toilet", "top", "touch",
    "tr", "uname", "uniq", "uptime", "vi", "vim", "wc", "wget", "which", "whoami", "yes",
];

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

type Reply = (Status, Json<CommandResponse>);

fn reply(code: Status, stdout: &str, stderr: &str, status: i32) -> Reply {
    (
        code,
        Json(CommandResponse {
            stdout: stdout.to_string(),
            stderr: stderr.to_string(),
            status,
        }),
    )
}

struct Telegram {
    token: String,
    chat_id: String,
}

struct App {
    fw: Arc<SandboxFw>,
    exec_limit: RateLimiter,
    message_cap: DailyCap,
    sandboxes: Arc<Semaphore>,
    http: reqwest::Client,
    telegram: Option<Telegram>,
    /// Portfolio pages under www/commands, read once at start.
    pages: Vec<String>,
    page_set: HashSet<String>,
}

fn non_empty_env(name: &str) -> Option<String> {
    std::env::var(name).ok().filter(|v| !v.trim().is_empty())
}

/// `portrait_exec_total{command}`: the first word, if it is a known command.
fn command_label(command: &str) -> &'static str {
    let first = command.split_whitespace().next().unwrap_or("");
    let first = first.rsplit('/').next().unwrap_or(first);
    KNOWN_COMMANDS
        .iter()
        .find(|c| **c == first)
        .copied()
        .unwrap_or("other")
}

/// Tab completion (`compgen -c|-f "<word>"`, tab-completion.js) as opposed to
/// a typed command. Anything with shell syntax counts as a typed command.
fn is_completion(command: &str) -> bool {
    command.starts_with("compgen ")
        && !command.chars().any(|c| {
            matches!(
                c,
                ';' | '|' | '&' | '$' | '`' | '\n' | '<' | '>' | '(' | ')'
            )
        })
}

/// At most `max` characters of a command for the log, on one line.
fn clip(command: &str, max: usize) -> String {
    let mut out: String = command.chars().take(max).collect();
    if command.chars().count() > max {
        out.push('…');
    }
    out
}

fn reject(reason: &'static str, ip: &str, code: Status, text: &str) -> Reply {
    METRICS.rejected.with_label_values(&[reason]).inc();
    telemetry::info(
        "exec",
        "command refused",
        json!({"event": "exec_rejected", "reason": reason, "ip": ip}),
    );
    reply(code, "", text, 1)
}

async fn send_message(app: &App, ip: Option<IpAddr>, ip_s: &str, message: &str) -> Reply {
    let finish = |result: &'static str| {
        METRICS.messages.with_label_values(&[result]).inc();
        // The text itself is never logged; its length is enough.
        telemetry::info(
            "message",
            "message to the owner",
            json!({"event": "message", "result": result, "ip": ip_s, "len": message.chars().count()}),
        );
    };
    if message.is_empty() {
        finish("empty");
        return reply(Status::Ok, "", "Error: No message provided", 1);
    }
    telemetry::feature("send_message");
    let Some(tg) = &app.telegram else {
        finish("not_configured");
        return reply(
            Status::Ok,
            "",
            "Error: messages are switched off on this site",
            1,
        );
    };
    if !app.message_cap.allow(ip) {
        finish("rate_limited");
        return reply(
            Status::TooManyRequests,
            "",
            "Error: too many messages today, please try again tomorrow",
            1,
        );
    }
    let url = format!("https://api.telegram.org/bot{}/sendMessage", tg.token);
    let response = app
        .http
        .post(&url)
        .json(&json!({"chat_id": tg.chat_id, "text": message}))
        .send()
        .await;
    match response {
        Ok(resp) if resp.status().is_success() => {
            finish("sent");
            reply(Status::Ok, "Message sent successfully", "", 0)
        }
        Ok(resp) => {
            let status = resp.status().as_u16();
            // Telegram's error description (e.g. "chat not found"); never the URL,
            // which carries the bot token.
            let body: String = resp
                .text()
                .await
                .unwrap_or_default()
                .chars()
                .take(300)
                .collect();
            finish("telegram_error");
            telemetry::error(
                "message",
                "Telegram refused the message",
                json!({"event": "message_failed", "error": "telegram_error", "status": status, "exc": body}),
            );
            reply(
                Status::Ok,
                "",
                "Error: the message could not be delivered, please try again later",
                1,
            )
        }
        Err(e) => {
            finish("network_error");
            telemetry::error(
                "message",
                "could not reach Telegram",
                json!({"event": "message_failed", "error": "network_error", "exc": e.without_url().to_string()}),
            );
            reply(
                Status::Ok,
                "",
                "Error: the message could not be delivered, please try again later",
                1,
            )
        }
    }
}

#[post("/execute", data = "<req>")]
async fn execute_command(app: &State<App>, ip: Option<IpAddr>, req: Json<CommandRequest>) -> Reply {
    // ip comes from X-Real-IP (set by SWAG), else the peer address.
    let ip_s = ip.map_or_else(|| "-".to_string(), |ip| ip.to_string());

    if req.command.len() > MAX_COMMAND_BYTES {
        return reject(
            "too_long",
            &ip_s,
            Status::PayloadTooLarge,
            "Error: command too long",
        );
    }
    if !app.exec_limit.allow(ip) {
        return reject(
            "rate_limit",
            &ip_s,
            Status::TooManyRequests,
            "Slow down a little: too many commands, try again in a few seconds",
        );
    }

    if let Some(message) = req.command.strip_prefix("message ") {
        return send_message(app, ip, &ip_s, message.trim()).await;
    }
    if req.command.trim() == "message" {
        return send_message(app, ip, &ip_s, "").await;
    }

    let completion = is_completion(&req.command);
    let kind = if completion { "completion" } else { "shell" };
    let label = if completion {
        "compgen"
    } else {
        command_label(&req.command)
    };
    telemetry::feature(if completion {
        "tab_complete"
    } else {
        "run_command"
    });

    let Ok(_permit) = app.sandboxes.clone().try_acquire_owned() else {
        return reject(
            "busy",
            &ip_s,
            Status::TooManyRequests,
            "The terminal is busy right now, try again in a few seconds",
        );
    };
    // Fail closed: no sandbox while its egress firewall is missing.
    if !app.fw.ensure().await {
        return reject(
            "sandbox_firewall",
            &ip_s,
            Status::ServiceUnavailable,
            "The terminal is under maintenance, try again later",
        );
    }
    let mut fw_watch = app.fw.subscribe();

    let mut cmd = tokio::process::Command::new("prlimit");
    cmd.arg("--cpu=5");
    // 128 MiB virtual address space. Ruby lolcat fails under 50 MiB, and
    // the failure point moves around 72-80 MiB depending on mapping layout.
    cmd.arg("--as=134217728");
    // Real uid 999 so the firewall's owner match applies. Root + bwrap --uid remaps skuid to 0.
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
        cmd.arg("--setenv")
            .arg("COLUMNS")
            .arg(width.clamp(10, 1000).to_string());
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
    cmd.kill_on_drop(true);
    // A pipe makes lolcat copy stdin unchanged. A pty makes stdout a tty so it
    // colorizes. stderr stays a pipe so success can still drop curl's meter.
    let pty_master = match open_guest_stdout(req.width) {
        Some((master, slave)) => {
            cmd.stdout(Stdio::from(slave));
            Some(master)
        }
        None => {
            telemetry::warning(
                "exec",
                "pty unavailable, stdout is a pipe",
                json!({"event": "pty_unavailable"}),
            );
            cmd.stdout(Stdio::piped());
            None
        }
    };
    cmd.stderr(Stdio::piped());

    let started = Instant::now();
    let mut child = match cmd.spawn() {
        Ok(c) => c,
        Err(e) => {
            METRICS
                .exec
                .with_label_values(&[label, "spawn_error"])
                .inc();
            telemetry::error(
                "exec",
                "could not start the sandbox",
                json!({"event": "exec_failed", "error": "spawn_error", "exc": e.to_string()}),
            );
            return reply(Status::Ok, "", "Failed to spawn command", -1);
        }
    };
    // Dropping the Command closes our copy of the pty slave, so the master
    // sees EOF once the guest exits.
    drop(cmd);
    METRICS.sandboxes_running.inc();

    let Some(mut stderr_reader) = child.stderr.take() else {
        METRICS.sandboxes_running.dec();
        return reply(Status::Ok, "", "Failed to spawn command", -1);
    };
    let stdout_task = if let Some(master) = pty_master {
        task::spawn_blocking(move || String::from_utf8_lossy(&read_pty_master(master)).into_owned())
    } else {
        let mut stdout_reader = child.stdout.take();
        task::spawn(async move {
            let mut buf = Vec::new();
            if let Some(r) = stdout_reader.as_mut() {
                let _ = r.read_to_end(&mut buf).await;
            }
            String::from_utf8_lossy(&buf).to_string()
        })
    };
    let stderr_task = task::spawn(async move {
        let mut buf = Vec::new();
        let _ = stderr_reader.read_to_end(&mut buf).await;
        String::from_utf8_lossy(&buf).to_string()
    });

    // Ends with the exit status, the timeout, or the firewall going missing.
    let fw_lost = async {
        loop {
            if fw_watch.changed().await.is_err() {
                std::future::pending::<()>().await;
            }
            if !*fw_watch.borrow() {
                return;
            }
        }
    };
    let outcome = tokio::select! {
        r = child.wait() => r.ok().map(|s| s.code().unwrap_or(-1)).ok_or("error"),
        _ = tokio::time::sleep(EXEC_TIMEOUT) => Err("timeout"),
        _ = fw_lost => Err("firewall_lost"),
    };

    let (stdout, mut stderr, status, result) = match outcome {
        Ok(code) => {
            let result = match code {
                0 => "ok",
                127 => "not_found",
                _ => "error",
            };
            (
                stdout_task.await.unwrap_or_default(),
                stderr_task.await.unwrap_or_default(),
                code,
                result,
            )
        }
        Err(reason) => {
            let _ = child.kill().await;
            let _ = child.wait().await;
            stdout_task.abort();
            stderr_task.abort();
            let text = if reason == "firewall_lost" {
                "Command stopped: the terminal is under maintenance"
            } else {
                "Command timed out"
            };
            (String::new(), text.to_string(), -1, reason)
        }
    };
    METRICS.sandboxes_running.dec();
    let elapsed = started.elapsed();
    METRICS
        .exec_duration
        .with_label_values(&[kind])
        .observe(elapsed.as_secs_f64());
    METRICS.exec.with_label_values(&[label, result]).inc();

    // One line per command, after it ended. Completions only at debug: one
    // per Tab key. {:?}-style escaping in `cmd` keeps a command on one line.
    let fields = json!({
        "event": "exec",
        "ip": ip_s,
        "kind": kind,
        "command": label,
        "result": result,
        "exit": status,
        "ms": elapsed.as_millis() as u64,
        "out_bytes": stdout.len(),
        "cmd": clip(&req.command, 200),
    });
    let level = if completion {
        telemetry::Level::Debug
    } else {
        telemetry::Level::Info
    };
    telemetry::log(level, "exec", "command finished", fields);
    if result == "firewall_lost" {
        telemetry::error(
            "exec",
            "sandbox stopped because its firewall went missing",
            json!({"event": "exec_killed", "error": "firewall_lost", "ip": ip_s}),
        );
    }

    // Curl's progress meter and similar noise go to stderr even on success.
    // The page renders stderr in red, so drop it when the command worked.
    if status == 0 {
        stderr.clear();
    }

    reply(Status::Ok, &stdout, &stderr, status)
}

#[get("/commands")]
fn get_commands(app: &State<App>) -> Json<Vec<String>> {
    Json(app.pages.clone())
}

fn read_pages() -> Vec<String> {
    let mut pages = Vec::new();
    match std::fs::read_dir("./www/commands") {
        Ok(entries) => {
            for entry in entries.flatten() {
                if let Some(filename) = entry.file_name().to_str() {
                    if let Some(page) = filename.strip_suffix(".html") {
                        pages.push(page.to_string());
                    }
                }
            }
        }
        Err(e) => telemetry::error(
            "server",
            "cannot read the portfolio pages",
            json!({"event": "pages_missing", "error": "io", "exc": e.to_string()}),
        ),
    }
    pages.sort();
    pages
}

/// Counts the static pages: `index` and each portfolio command page.
struct PageViews;

#[rocket::async_trait]
impl Fairing for PageViews {
    fn info(&self) -> Info {
        Info {
            name: "page views",
            kind: Kind::Response,
        }
    }

    async fn on_response<'r>(&self, req: &'r Request<'_>, res: &mut Response<'r>) {
        if req.method() != Method::Get || res.status() != Status::Ok {
            return;
        }
        let path = req.uri().path();
        let path = path.as_str();
        if path == "/" || path == "/index.html" {
            METRICS.page_views.with_label_values(&["index"]).inc();
            return;
        }
        let Some(page) = path
            .strip_prefix("/commands/")
            .and_then(|p| p.strip_suffix(".html"))
        else {
            return;
        };
        let known = req
            .rocket()
            .state::<App>()
            .is_some_and(|app| app.page_set.contains(page));
        METRICS
            .page_views
            .with_label_values(&[if known { page } else { "other" }])
            .inc();
        telemetry::feature("open_page");
    }
}

#[rocket::main]
async fn main() {
    telemetry::setup_logging();
    telemetry::build_info(
        &std::env::var("PORTRAIT_VERSION").unwrap_or_else(|_| env!("CARGO_PKG_VERSION").into()),
    );

    let fw = Arc::new(SandboxFw::new());
    if fw.required && !fw.ensure().await {
        telemetry::log(
            telemetry::Level::Critical,
            "sandbox_fw",
            "cannot install the sandbox firewall; refusing to start",
            json!({"event": "sandbox_fw", "state": "missing", "error": "sandbox_fw_missing"}),
        );
        std::process::exit(1);
    }
    fw.clone().spawn_watchdog();
    telemetry::start_metrics();

    let telegram = match (
        non_empty_env("TELEGRAM_BOT_TOKEN"),
        non_empty_env("TELEGRAM_CHAT_ID"),
    ) {
        (Some(token), Some(chat_id)) => Some(Telegram { token, chat_id }),
        _ => {
            telemetry::info(
                "message",
                "Telegram is not set up; the message command answers with an error",
                json!({"event": "message_not_configured"}),
            );
            None
        }
    };
    let pages = read_pages();
    let app = App {
        fw,
        exec_limit: RateLimiter::new(
            env_num("PORTRAIT_EXEC_PER_SECOND", 1.0),
            env_num("PORTRAIT_EXEC_BURST", 10.0),
        ),
        message_cap: DailyCap::new(
            env_num("PORTRAIT_MESSAGES_PER_IP_DAY", 5),
            env_num("PORTRAIT_MESSAGES_PER_DAY", 50),
        ),
        sandboxes: Arc::new(Semaphore::new(env_num("PORTRAIT_MAX_SANDBOXES", 8))),
        http: reqwest::Client::builder()
            .timeout(Duration::from_secs(15))
            .build()
            .unwrap_or_default(),
        telegram,
        page_set: pages.iter().cloned().collect(),
        pages,
    };

    let figment = rocket::Config::figment()
        .merge(("limits", Limits::default().limit("json", 16.kibibytes())));
    let result = rocket::custom(figment)
        .manage(app)
        .attach(PageViews)
        .mount("/", FileServer::from("./www").rank(1))
        .mount("/", routes![execute_command, get_commands])
        .launch()
        .await;
    if let Err(e) = result {
        telemetry::log(
            telemetry::Level::Critical,
            "server",
            "server stopped with an error",
            json!({"event": "server_failed", "error": "launch", "exc": e.to_string()}),
        );
        std::process::exit(1);
    }
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
        let slave_fd = libc::open(
            name.as_ptr(),
            libc::O_RDWR | libc::O_NOCTTY | libc::O_CLOEXEC,
        );
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
        Some((File::from_raw_fd(master_fd), File::from_raw_fd(slave_fd)))
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

#[cfg(test)]
mod tests {
    use super::{command_label, is_completion, open_guest_stdout, read_pty_master};

    #[test]
    fn command_label_is_bounded() {
        assert_eq!(command_label("figlet hi | lolcat"), "figlet");
        assert_eq!(command_label("  /bin/ls -la"), "ls");
        assert_eq!(command_label("rm -rf /"), "rm");
        assert_eq!(command_label("my-secret-tool --x"), "other");
        assert_eq!(command_label(""), "other");
    }

    #[test]
    fn completion_needs_plain_compgen() {
        assert!(is_completion("compgen -c \"fig\""));
        assert!(!is_completion("compgen -c x; curl evil"));
        assert!(!is_completion("ls"));
    }
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
