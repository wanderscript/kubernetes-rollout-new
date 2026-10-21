#!/usr/bin/env python3
"""Continuous HTTP load generator; reports request counts, status codes, and latency."""
import argparse
import concurrent.futures
import time
import urllib.error
import urllib.request
from collections import Counter
from statistics import mean

def one_request(url, timeout):
    started = time.perf_counter()
    status = 0
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "rollout-lab-loadtest"})
        with urllib.request.urlopen(req, timeout=timeout) as response:
            status = response.status
            response.read()
    except urllib.error.HTTPError as exc:
        status = exc.code
        exc.read()
    except Exception:
        status = 0
    return status, time.perf_counter() - started

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default="http://127.0.0.1:18080/")
    parser.add_argument("--duration", type=int, default=180)
    parser.add_argument("--concurrency", type=int, default=10)
    parser.add_argument("--timeout", type=float, default=3.0)
    args = parser.parse_args()

    counts = Counter()
    latencies = []
    deadline = time.monotonic() + args.duration
    total = 0
    print(f"Target={args.url} duration={args.duration}s concurrency={args.concurrency}", flush=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.concurrency) as pool:
        pending = set()
        while time.monotonic() < deadline or pending:
            while time.monotonic() < deadline and len(pending) < args.concurrency:
                pending.add(pool.submit(one_request, args.url, args.timeout))
            done, pending = concurrent.futures.wait(
                pending, timeout=0.2, return_when=concurrent.futures.FIRST_COMPLETED
            )
            for future in done:
                status, latency = future.result()
                counts[status] += 1
                latencies.append(latency)
                total += 1
                if total % 100 == 0:
                    errors = sum(v for k, v in counts.items() if k == 0 or k >= 500)
                    print(f"progress requests={total} errors={errors}", flush=True)

    errors = sum(v for k, v in counts.items() if k == 0 or k >= 500)
    ordered = sorted(latencies)
    p95 = ordered[min(len(ordered)-1, int(0.95 * len(ordered)))] if ordered else 0
    print("\n=== RESULT ===")
    print(f"requests_total={total}")
    print(f"responses_by_status={dict(counts)}")
    print(f"transport_or_5xx_errors={errors}")
    print(f"error_rate={(errors / total * 100) if total else 0:.4f}%")
    print(f"latency_mean_ms={(mean(latencies) * 1000) if latencies else 0:.2f}")
    print(f"latency_p95_ms={p95 * 1000:.2f}")
    if errors:
        raise SystemExit(2)

if __name__ == "__main__":
    main()
