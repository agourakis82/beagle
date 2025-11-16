#!/usr/bin/env python3
"""Test BEAGLE SDK"""

from beagle_client import BeagleClient


def main():
    print("🧪 Testing BEAGLE SDK...")
    client = BeagleClient()
    # Health check
    print("\n1. Health Check:")
    health = client.health_check()
    for service, status in health.items():
        emoji = "✅" if status else "❌"
        print(f"  {emoji} {service}: {'UP' if status else 'DOWN'}")
    # Test generation (if vLLM is up)
    if health.get("vllm"):
        print("\n2. Text Generation Test:")
        try:
            text = client.generate_text(
                prompt="Biomaterials are",
                max_tokens=50,
                temperature=0.7,
            )
            print(f"  Generated: {text[:100]}...")
        except Exception as e:
            print(f"  ❌ Error: {e}")
    else:
        print("\n2. Text Generation Test: SKIPPED (vLLM not ready)")
    print("\n✅ SDK test complete!")


if __name__ == "__main__":
    main()


