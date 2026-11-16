//! Keeps the sandbox egress firewall (scripts/apply-sandbox-fw.sh) in place.
//!
//! The firewall has two layers: an nftables table of its own (`inet
//! portrait-sandbox`) and owner-match rules at the top of iptables' OUTPUT
//! chain. When gluetun restores its own OUTPUT rules it replaces the iptables
//! layer only; the nftables table is left alone, so the sandbox stays closed.
//!
//! `apply-sandbox-fw.sh --check` exits 0 when both layers are in place, 2 when
//! only the iptables layer is missing (still closed, repaired here) and 1 when
//! the nftables layer is missing (open). The server checks before each
//! sandbox starts and every few seconds; while the firewall is missing it
//! refuses commands and kills sandboxes that are running.

use crate::telemetry::{self, METRICS};
use serde_json::json;
use std::time::Duration;
use tokio::process::Command;
use tokio::sync::{watch, Mutex};

const SCRIPT: &str = "/usr/local/bin/apply-sandbox-fw.sh";
const LOGGER: &str = "sandbox_fw";

#[derive(Debug, PartialEq, Eq)]
enum State {
    Ok,
    /// Closed, but the iptables layer needs to be put back.
    Partial,
    Missing,
}

pub struct SandboxFw {
    /// `PORTRAIT_SANDBOX_FW=1`: Neo always sets it. Local `docker run` without
    /// NET_ADMIN leaves it unset, and then nothing is enforced.
    pub required: bool,
    ok: watch::Sender<bool>,
    lock: Mutex<()>,
}

async fn run(args: &[&str]) -> (Option<i32>, String) {
    let out = tokio::time::timeout(
        Duration::from_secs(10),
        Command::new(SCRIPT).args(args).kill_on_drop(true).output(),
    )
    .await;
    match out {
        Ok(Ok(o)) => {
            let mut text = String::from_utf8_lossy(&o.stdout).into_owned();
            text.push_str(&String::from_utf8_lossy(&o.stderr));
            (o.status.code(), text.trim().to_string())
        }
        Ok(Err(e)) => (None, e.to_string()),
        Err(_) => (None, "timed out".into()),
    }
}

async fn check() -> State {
    match run(&["--check"]).await.0 {
        Some(0) => State::Ok,
        Some(2) => State::Partial,
        _ => State::Missing,
    }
}

impl SandboxFw {
    pub fn new() -> Self {
        let required = std::env::var("PORTRAIT_SANDBOX_FW").as_deref() == Ok("1");
        let (ok, _) = watch::channel(!required);
        SandboxFw {
            required,
            ok,
            lock: Mutex::new(()),
        }
    }

    /// Tells running sandboxes when the firewall goes missing.
    pub fn subscribe(&self) -> watch::Receiver<bool> {
        self.ok.subscribe()
    }

    fn set(&self, ok: bool) {
        METRICS.fw_ok.set(i64::from(ok));
        self.ok.send_replace(ok);
    }

    /// Check the firewall, repair it when needed; true when the sandbox is closed.
    pub async fn ensure(&self) -> bool {
        if !self.required {
            return true;
        }
        let _guard = self.lock.lock().await;
        match check().await {
            State::Ok => {
                self.set(true);
                true
            }
            State::Partial => {
                let (code, out) = run(&[]).await;
                let repaired = code == Some(0);
                METRICS
                    .fw_repairs
                    .with_label_values(&[if repaired { "repaired" } else { "failed" }])
                    .inc();
                telemetry::warning(
                    LOGGER,
                    "iptables layer of the sandbox firewall was replaced (gluetun restored its rules); put back",
                    json!({"event": "sandbox_fw", "state": "partial", "repaired": repaired, "output": out}),
                );
                // The nftables layer still holds.
                self.set(true);
                true
            }
            State::Missing => {
                // Kill running sandboxes first, then repair.
                self.set(false);
                let (code, out) = run(&[]).await;
                let ok = code == Some(0) && check().await == State::Ok;
                METRICS
                    .fw_repairs
                    .with_label_values(&[if ok { "repaired" } else { "failed" }])
                    .inc();
                if ok {
                    telemetry::warning(
                        LOGGER,
                        "sandbox firewall was missing; reinstalled",
                        json!({"event": "sandbox_fw", "state": "restored", "output": out}),
                    );
                } else {
                    telemetry::error(
                        LOGGER,
                        "sandbox firewall is missing and could not be installed; commands are refused",
                        json!({"event": "sandbox_fw", "state": "missing", "error": "sandbox_fw_missing", "output": out}),
                    );
                }
                self.set(ok);
                ok
            }
        }
    }

    /// Re-check every few seconds for the life of the server.
    pub fn spawn_watchdog(self: std::sync::Arc<Self>) {
        if !self.required {
            return;
        }
        tokio::spawn(async move {
            let mut tick = tokio::time::interval(Duration::from_secs(5));
            tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
            loop {
                tick.tick().await;
                self.ensure().await;
            }
        });
    }
}
