//! Neo app telemetry for this Rust server.
//!
//! Neo ships copyable helpers for Python and Node only
//! (`templates/plugin/telemetry/python/neo_telemetry.py`). This module keeps the
//! same contract (docs/APP-TELEMETRY.md in Neo):
//!
//! - logs: one JSON object per line on stdout with `ts`, `level`
//!   (debug|info|warning|error|critical), `logger`, `msg` and extra fields;
//!   every error line also counts in `neo_app_errors_total{component, kind}`;
//! - metrics: `neo_app_feature_used_total{feature}`, `neo_app_errors_total`,
//!   `neo_app_build_info{version}` plus the app's own `portrait_*` metrics,
//!   served on `$NEO_METRICS_PORT` (Neo sets it only while monitoring collects).

use prometheus::{
    Encoder, HistogramOpts, HistogramVec, IntCounterVec, IntGauge, IntGaugeVec, Opts, Registry,
    TextEncoder,
};
use serde_json::{Map, Value};
use std::io::Write;
use std::sync::LazyLock;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tokio::io::{AsyncReadExt, AsyncWriteExt};

pub struct Metrics {
    registry: Registry,
    features: IntCounterVec,
    errors: IntCounterVec,
    build_info: IntGaugeVec,
    /// Sandboxed commands by top-level command name (fixed allow-list) and result.
    pub exec: IntCounterVec,
    /// Spawn → exit of one sandbox, by kind (shell|completion).
    pub exec_duration: HistogramVec,
    pub sandboxes_running: IntGauge,
    /// Requests refused before a sandbox started, by reason.
    pub rejected: IntCounterVec,
    /// `message` commands by result (sent, telegram_error, …).
    pub messages: IntCounterVec,
    /// Static pages served: index and the portfolio commands.
    pub page_views: IntCounterVec,
    /// 1 while the sandbox egress firewall is in place, 0 while it is missing.
    pub fw_ok: IntGauge,
    /// Firewall repairs by result (repaired|failed).
    pub fw_repairs: IntCounterVec,
}

fn counter(registry: &Registry, name: &str, help: &str, labels: &[&str]) -> IntCounterVec {
    let c = IntCounterVec::new(Opts::new(name, help), labels).expect("valid counter");
    registry
        .register(Box::new(c.clone()))
        .expect("unique counter");
    c
}

fn gauge(registry: &Registry, name: &str, help: &str) -> IntGauge {
    let g = IntGauge::new(name, help).expect("valid gauge");
    registry
        .register(Box::new(g.clone()))
        .expect("unique gauge");
    g
}

pub static METRICS: LazyLock<Metrics> = LazyLock::new(|| {
    let registry = Registry::new();
    let features = counter(
        &registry,
        "neo_app_feature_used_total",
        "Uses of a feature.",
        &["feature"],
    );
    let errors = counter(
        &registry,
        "neo_app_errors_total",
        "Errors by component and kind.",
        &["component", "kind"],
    );
    let build_info = IntGaugeVec::new(
        Opts::new("neo_app_build_info", "App version."),
        &["version"],
    )
    .expect("valid gauge");
    registry
        .register(Box::new(build_info.clone()))
        .expect("unique gauge");
    let exec = counter(
        &registry,
        "portrait_exec_total",
        "Sandboxed commands by top-level command and result.",
        &["command", "result"],
    );
    let exec_duration = HistogramVec::new(
        HistogramOpts::new(
            "portrait_exec_duration_seconds",
            "Time one sandboxed command ran.",
        )
        .buckets(vec![0.05, 0.1, 0.25, 0.5, 1.0, 2.0, 5.0, 10.0]),
        &["kind"],
    )
    .expect("valid histogram");
    registry
        .register(Box::new(exec_duration.clone()))
        .expect("unique histogram");
    let sandboxes_running = gauge(
        &registry,
        "portrait_sandboxes_running",
        "Sandboxes running right now.",
    );
    let rejected = counter(
        &registry,
        "portrait_exec_rejected_total",
        "Commands refused before a sandbox started.",
        &["reason"],
    );
    let messages = counter(
        &registry,
        "portrait_messages_total",
        "Messages to the owner by result.",
        &["result"],
    );
    let page_views = counter(
        &registry,
        "portrait_page_views_total",
        "Pages served by name.",
        &["page"],
    );
    let fw_ok = gauge(
        &registry,
        "portrait_sandbox_fw_ok",
        "1 while the sandbox firewall is in place.",
    );
    let fw_repairs = counter(
        &registry,
        "portrait_sandbox_fw_repairs_total",
        "Sandbox firewall repairs by result.",
        &["result"],
    );
    Metrics {
        registry,
        features,
        errors,
        build_info,
        exec,
        exec_duration,
        sandboxes_running,
        rejected,
        messages,
        page_views,
        fw_ok,
        fw_repairs,
    }
});

/// One use of a user-visible action. `name` is a code constant, never user input.
pub fn feature(name: &'static str) {
    METRICS.features.with_label_values(&[name]).inc();
}

pub fn build_info(version: &str) {
    let v = if version.is_empty() {
        "unknown"
    } else {
        version
    };
    METRICS.build_info.with_label_values(&[v]).set(1);
}

// ── Logging ─────────────────────────────────────────────────────────────────

#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum Level {
    Debug,
    Info,
    Warning,
    Error,
    Critical,
}

impl Level {
    fn as_str(self) -> &'static str {
        match self {
            Level::Debug => "debug",
            Level::Info => "info",
            Level::Warning => "warning",
            Level::Error => "error",
            Level::Critical => "critical",
        }
    }
}

static MIN_LEVEL: LazyLock<Level> = LazyLock::new(|| {
    match std::env::var("LOG_LEVEL")
        .unwrap_or_default()
        .to_ascii_lowercase()
        .as_str()
    {
        "debug" | "trace" => Level::Debug,
        "warning" | "warn" => Level::Warning,
        "error" => Level::Error,
        "critical" => Level::Critical,
        _ => Level::Info,
    }
});

/// RFC 3339 UTC with milliseconds, like the Python helper (`2026-11-16T08:52:22.599Z`).
fn timestamp(now: SystemTime) -> String {
    let d = now.duration_since(UNIX_EPOCH).unwrap_or(Duration::ZERO);
    let secs = d.as_secs() as i64;
    let (days, rem) = (secs.div_euclid(86_400), secs.rem_euclid(86_400));
    // Civil date from days since 1970-01-01 (Howard Hinnant's algorithm).
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = yoe + era * 400 + i64::from(month <= 2);
    format!(
        "{:04}-{:02}-{:02}T{:02}:{:02}:{:02}.{:03}Z",
        year,
        month,
        day,
        rem / 3600,
        (rem % 3600) / 60,
        rem % 60,
        d.subsec_millis()
    )
}

/// Write one JSON log line. `fields` (an object) adds extra keys such as `event`.
/// Lines at error or above count in `neo_app_errors_total{component=logger, kind}`,
/// `kind` being the `error` field when there is one.
pub fn log(level: Level, logger: &str, msg: &str, fields: Value) {
    if level >= Level::Error {
        let kind = fields
            .get("error")
            .and_then(Value::as_str)
            .unwrap_or("log")
            .to_string();
        let component = logger.split("::").next().unwrap_or(logger);
        METRICS.errors.with_label_values(&[component, &kind]).inc();
    }
    if level < *MIN_LEVEL {
        return;
    }
    let mut out = Map::new();
    out.insert("ts".into(), Value::String(timestamp(SystemTime::now())));
    out.insert("level".into(), Value::String(level.as_str().into()));
    out.insert("logger".into(), Value::String(logger.into()));
    out.insert("msg".into(), Value::String(msg.into()));
    if let Value::Object(extra) = fields {
        for (k, v) in extra {
            out.entry(k).or_insert(v);
        }
    }
    let line = Value::Object(out).to_string();
    let mut stdout = std::io::stdout().lock();
    let _ = writeln!(stdout, "{line}");
    let _ = stdout.flush();
}

pub fn info(logger: &str, msg: &str, fields: Value) {
    log(Level::Info, logger, msg, fields);
}

pub fn warning(logger: &str, msg: &str, fields: Value) {
    log(Level::Warning, logger, msg, fields);
}

pub fn error(logger: &str, msg: &str, fields: Value) {
    log(Level::Error, logger, msg, fields);
}

/// Routes the `log` crate (Rocket, hyper, reqwest) into the same JSON lines.
/// Rocket only installs its own logger when none is set yet.
struct JsonLogger;

impl log::Log for JsonLogger {
    fn enabled(&self, _: &log::Metadata) -> bool {
        true
    }

    fn log(&self, record: &log::Record) {
        let target = record.target();
        let msg = record.args().to_string();
        let mut level = match record.level() {
            log::Level::Error => Level::Error,
            log::Level::Warn => Level::Warning,
            log::Level::Info => Level::Info,
            log::Level::Debug | log::Level::Trace => Level::Debug,
        };
        if target.starts_with("rocket") {
            if target.starts_with("rocket::launch") {
                // The launch headlines come at warn and are plain information;
                // the config dump below them (info) is left out.
                if record.level() > log::Level::Warn {
                    return;
                }
                level = Level::Info;
            } else if msg.starts_with("No matching routes")
                || msg.starts_with("Responding with registered")
                || msg.contains("catcher registered")
                || msg.contains("kind: NotFound")
            {
                // Every 404 from a scanner: SWAG's access log already has it.
                return;
            } else if level < Level::Warning {
                // Per-request routing chatter duplicates SWAG's access log.
                return;
            }
        } else if level < Level::Warning {
            // hyper/reqwest internals.
            return;
        }
        let logger = target.split("::").next().unwrap_or(target);
        log(level, logger, msg.trim(), Value::Object(Map::new()));
    }

    fn flush(&self) {}
}

/// JSON logs for this process: `log` crate records and panics.
pub fn setup_logging() {
    if log::set_boxed_logger(Box::new(JsonLogger)).is_ok() {
        log::set_max_level(log::LevelFilter::Info);
    }
    std::panic::set_hook(Box::new(|info| {
        let msg = info
            .payload()
            .downcast_ref::<&str>()
            .map(|s| s.to_string())
            .or_else(|| info.payload().downcast_ref::<String>().cloned())
            .unwrap_or_else(|| "panic".into());
        let location = info
            .location()
            .map(|l| format!("{}:{}", l.file(), l.line()))
            .unwrap_or_default();
        log(
            Level::Critical,
            "unhandled",
            "panic",
            serde_json::json!({"event": "panic", "error": "panic", "exc": msg, "location": location}),
        );
    }));
}

// ── Metrics endpoint ────────────────────────────────────────────────────────

fn encode() -> Vec<u8> {
    let mut buf = Vec::new();
    if let Err(e) = TextEncoder::new().encode(&METRICS.registry.gather(), &mut buf) {
        error(
            "telemetry",
            "encoding metrics failed",
            serde_json::json!({"error": "encode", "exc": e.to_string()}),
        );
    }
    buf
}

/// Serve `GET /metrics` on `$NEO_METRICS_PORT`; does nothing when it is unset.
/// A tiny HTTP/1.1 responder: the agent scrapes, nothing else talks to it.
pub fn start_metrics() -> bool {
    let Some(port) = std::env::var("NEO_METRICS_PORT")
        .ok()
        .and_then(|p| p.parse::<u16>().ok())
    else {
        return false;
    };
    tokio::spawn(async move {
        let listener = match tokio::net::TcpListener::bind(("0.0.0.0", port)).await {
            Ok(l) => l,
            Err(e) => {
                error(
                    "telemetry",
                    "metrics port unavailable",
                    serde_json::json!({"event": "metrics_bind_failed", "port": port, "error": "bind", "exc": e.to_string()}),
                );
                return;
            }
        };
        info(
            "telemetry",
            &format!("metrics on :{port}"),
            serde_json::json!({"event": "metrics_started"}),
        );
        loop {
            let (mut sock, _) = match listener.accept().await {
                Ok(s) => s,
                Err(_) => continue,
            };
            tokio::spawn(async move {
                let mut buf = [0u8; 2048];
                let n =
                    match tokio::time::timeout(Duration::from_secs(5), sock.read(&mut buf)).await {
                        Ok(Ok(n)) => n,
                        _ => return,
                    };
                let head = String::from_utf8_lossy(&buf[..n]);
                let path = head.split_whitespace().nth(1).unwrap_or("");
                let is_metrics = head.starts_with("GET ")
                    && (path == "/metrics" || path.starts_with("/metrics?"));
                let (status, body) = if is_metrics {
                    ("200 OK", encode())
                } else {
                    ("404 Not Found", b"not found\n".to_vec())
                };
                let header = format!(
                    "HTTP/1.1 {status}\r\nContent-Type: text/plain; version=0.0.4; charset=utf-8\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
                    body.len()
                );
                let _ = sock.write_all(header.as_bytes()).await;
                let _ = sock.write_all(&body).await;
                let _ = sock.shutdown().await;
            });
        }
    });
    true
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn timestamp_is_rfc3339_utc() {
        let t = UNIX_EPOCH + Duration::from_millis(1_794_819_142_599);
        assert_eq!(timestamp(t), "2026-11-16T08:52:22.599Z");
        assert_eq!(timestamp(UNIX_EPOCH), "1970-01-01T00:00:00.000Z");
    }

    #[test]
    fn errors_are_counted_and_metrics_encode() {
        let before = METRICS.errors.with_label_values(&["test", "boom"]).get();
        log(
            Level::Error,
            "test",
            "failed",
            serde_json::json!({"error": "boom"}),
        );
        assert_eq!(
            METRICS.errors.with_label_values(&["test", "boom"]).get(),
            before + 1
        );
        feature("run_command");
        let text = String::from_utf8(encode()).unwrap();
        assert!(text.contains("neo_app_feature_used_total{feature=\"run_command\"}"));
        assert!(text.contains("neo_app_errors_total{component=\"test\",kind=\"boom\"}"));
    }
}
