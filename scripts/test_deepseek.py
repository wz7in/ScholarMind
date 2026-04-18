import argparse
import os
import sys
import time

from deepseek_http import (
    SILICONFLOW_ENDPOINT,
    SILICONFLOW_MODEL,
    call_deepseek_chat,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Test DeepSeek call via SiliconFlow native HTTP"
    )
    parser.add_argument(
        "prompt",
        nargs="?",
        default="请用3句话总结 ScholarMind 这个科研工具的核心价值。",
        help="Prompt to send to DeepSeek",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=240,
        help="Request timeout in seconds (default: 240)",
    )
    parser.add_argument(
        "--out",
        default="",
        help="Optional output file path to save response text",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    has_sf_key = bool(os.getenv("SILICONFLOW_API_KEY"))
    has_ai_key = bool(os.getenv("AI_API_KEY"))

    print("=== DeepSeek HTTP Test ===")
    print(f"Endpoint: {SILICONFLOW_ENDPOINT}")
    print(f"Model: {SILICONFLOW_MODEL}")
    print(f"SILICONFLOW_API_KEY set: {has_sf_key}")
    print(f"AI_API_KEY set: {has_ai_key}")
    print(f"Timeout: {args.timeout}s")
    print("--- Prompt ---")
    print(args.prompt)

    start = time.perf_counter()
    try:
        response_text = call_deepseek_chat(args.prompt, timeout=args.timeout)
    except Exception as exc:
        elapsed = time.perf_counter() - start
        print(f"\n[FAILED] {exc}")
        print(f"Elapsed: {elapsed:.2f}s")
        return 1

    elapsed = time.perf_counter() - start
    print("\n--- Response ---")
    print(response_text)
    print(f"\n[SUCCESS] Elapsed: {elapsed:.2f}s")

    if args.out:
        with open(args.out, "w", encoding="utf-8") as f:
            f.write(response_text)
        print(f"Saved to: {args.out}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
