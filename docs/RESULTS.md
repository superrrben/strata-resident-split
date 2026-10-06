# Results

Reference machine: 2x RTX 3090 24 GB, 92 GiB RAM, both cards PCIe x8 (bifurcation off), GPUs limited to 220 W and 1500 MHz, engine Strata 0.1.39 with both patches, `--pcie-frac 0`, int8 KV, 262,144 context, MTP draft `--spec 4`. All rows in the same measurement window, two runs each unless one is shown. Throughput is decode tok/s on short agentic turns; deep decode and prefill are measured at 60K / 128K / 250K tokens of context.

## UD-Q4_K_XL (111 GB, 71.7 GiB of experts)

| | greedy | sampled | deep decode 60K / 128K / 250K | deep prefill 60K / 128K / 250K | RAM free | needles at 128K |
|---|---|---|---|---|---:|---|
| resident split (this repo) | 66.7, 67.3 | 69.0, 70.1 | 57.2 / 65.9 / 66.5 | 1966 / 2000 / 2048 | 33 GiB | 3/3 |
| stock `--mmap-experts` | 45.5 | 51.6 | 39.8 / 60.2 / 57.5 | 1556 / 1599 / 1636 | 72 GiB | 3/3 |

- The cards hold 11,537 of 24,576 experts (33.7 GiB, about 97.8% of the routed mass by the expert profile); 38.03 GiB are page-locked in RAM.
- Load: healthy after ~45 s.
- Conversation parking on this build (12 GiB cache, 6 slots), parent 145K + two children of 66K tokens, 4 rounds: 0 of 9 later turns without reuse, later rounds 2.3-3.3 s, no evictions, 26 GiB RAM still available with all three parked.
- Parked-and-restored answers equal a no-switching control: 6/6 short, 3/3 at 127K.
- `tests/tool-choice-probes.py` (N=5): every probe passes.

## For scale: the same GGUF family at UD-IQ4_XS (55 GiB experts), same mode

| | greedy | sampled | RAM free |
|---|---|---|---:|
| IQ4_XS resident split | 80.2, 79.4 | 83.9, 83.1 | 50 GiB |
| Q4_K_XL resident split | 66.7, 67.3 | 69.0, 70.1 | 33 GiB |

Q4_K_XL costs ~16% decode and ~17% prefill against IQ4_XS, and 17 GiB of RAM.

## Caveats

- One machine, one driver, one window. Single deep-decode samples vary by about +-5%.
- The engine is not bit-repeatable across restarts, so exact-match checks against stock Strata were not possible.
- Not measured: the pinned split (needs ~135 GiB), other GPU counts, cards with less than 24 GB, AMD (upstream says the Q4_K / Q5_K prompt kernels are NVIDIA-only), vision, a 250K-token park.
- Numbers come from a private harness (pi agent turns plus probe scripts) that is not in this repo; `tests/tool-choice-probes.py` is the only script shipped. A reproducible benchmark script is a good first contribution.
