"""Deterministic independent SPI-slave byte vectors: MODE, TX, RX."""
from pathlib import Path
import random

root = Path(__file__).resolve().parents[1]
rng = random.Random(23086083)
vectors = []
for mode in range(4):
    for tx in (0x00, 0xFF, 0xAA, 0x55):
        vectors.append((mode, tx, tx ^ 0xA5))
for i in range(1000):
    vectors.append((i % 4, rng.randrange(256), rng.randrange(256)))
out = root / "tb" / "vectors.hex"
out.write_text("".join(f"{(mode << 16) | (tx << 8) | rx:05x}\n" for mode, tx, rx in vectors))
print(f"Generated {len(vectors)} vectors (seed=23086083): {out}")
