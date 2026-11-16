//! Abuse limits for the public command endpoint: a token bucket per client
//! address, and daily caps for messages to the owner.

use std::collections::HashMap;
use std::net::{IpAddr, Ipv4Addr};
use std::sync::Mutex;
use std::time::{Instant, SystemTime, UNIX_EPOCH};

/// Reads a number from the environment, falling back to `default`.
pub fn env_num<T: std::str::FromStr>(name: &str, default: T) -> T {
    std::env::var(name)
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(default)
}

const MAX_TRACKED: usize = 50_000;

fn key(ip: Option<IpAddr>) -> IpAddr {
    // No address at all (no proxy header, no peer): one shared bucket.
    ip.unwrap_or(IpAddr::V4(Ipv4Addr::UNSPECIFIED))
}

pub struct RateLimiter {
    per_second: f64,
    burst: f64,
    buckets: Mutex<HashMap<IpAddr, (f64, Instant)>>,
}

impl RateLimiter {
    pub fn new(per_second: f64, burst: f64) -> Self {
        RateLimiter {
            per_second,
            burst: burst.max(1.0),
            buckets: Mutex::new(HashMap::new()),
        }
    }

    /// Takes one token for this client; false when it has none left.
    pub fn allow(&self, ip: Option<IpAddr>) -> bool {
        self.allow_at(key(ip), Instant::now())
    }

    fn allow_at(&self, ip: IpAddr, now: Instant) -> bool {
        let Ok(mut buckets) = self.buckets.lock() else {
            return true;
        };
        if buckets.len() > MAX_TRACKED {
            let (rate, burst) = (self.per_second, self.burst);
            buckets.retain(|_, (tokens, last)| {
                *tokens + now.duration_since(*last).as_secs_f64() * rate < burst
            });
        }
        let (tokens, last) = buckets.entry(ip).or_insert((self.burst, now));
        *tokens =
            (*tokens + now.duration_since(*last).as_secs_f64() * self.per_second).min(self.burst);
        *last = now;
        if *tokens >= 1.0 {
            *tokens -= 1.0;
            true
        } else {
            false
        }
    }
}

fn today() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() / 86_400)
        .unwrap_or(0)
}

/// At most `per_ip` per client and `total` overall per UTC day.
pub struct DailyCap {
    per_ip: u32,
    total: u32,
    state: Mutex<(u64, u32, HashMap<IpAddr, u32>)>,
}

impl DailyCap {
    pub fn new(per_ip: u32, total: u32) -> Self {
        DailyCap {
            per_ip,
            total,
            state: Mutex::new((0, 0, HashMap::new())),
        }
    }

    pub fn allow(&self, ip: Option<IpAddr>) -> bool {
        self.allow_on(key(ip), today())
    }

    fn allow_on(&self, ip: IpAddr, day: u64) -> bool {
        let Ok(mut state) = self.state.lock() else {
            return false;
        };
        let (current, total, per_ip) = &mut *state;
        if *current != day {
            *current = day;
            *total = 0;
            per_ip.clear();
        }
        let used = per_ip.get(&ip).copied().unwrap_or(0);
        if *total >= self.total || used >= self.per_ip {
            return false;
        }
        *total += 1;
        per_ip.insert(ip, used + 1);
        true
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    #[test]
    fn bucket_refills() {
        let l = RateLimiter::new(1.0, 2.0);
        let ip: IpAddr = "192.0.2.1".parse().unwrap();
        let t = Instant::now();
        assert!(l.allow_at(ip, t));
        assert!(l.allow_at(ip, t));
        assert!(!l.allow_at(ip, t));
        let other: IpAddr = "192.0.2.2".parse().unwrap();
        assert!(l.allow_at(other, t));
        assert!(l.allow_at(ip, t + Duration::from_millis(1100)));
    }

    #[test]
    fn daily_cap_per_ip_and_total() {
        let c = DailyCap::new(2, 3);
        let a: IpAddr = "192.0.2.1".parse().unwrap();
        let b: IpAddr = "192.0.2.2".parse().unwrap();
        assert!(c.allow_on(a, 1));
        assert!(c.allow_on(a, 1));
        assert!(!c.allow_on(a, 1));
        assert!(c.allow_on(b, 1));
        assert!(!c.allow_on(b, 1)); // total reached
        assert!(c.allow_on(a, 2)); // next day
    }
}
