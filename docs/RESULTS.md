# Results

Reference machine: 2x RTX 3090 24 GB, 92 GiB RAM, both cards PCIe x8 (bifurcation off), engine Strata 0.1.39 with both patches, `--pcie-frac 0`, int8 KV, 262,144 context, MTP draft `--spec 4`. Two runs each unless one is shown; rows compared within one table were measured in the same window unless noted. Throughput is decode tok/s on short agentic turns; deep decode and prefill are measured at 60K / 128K / 250K tokens of context.

## Power limits: stock against capped (2026-10-06, same day, same image and config)

"Stock" = the cards' default limits (390 W / 350 W), no clock lock. "Capped" = 220 W power cap plus a 1500 MHz clock lock plus an undervolt profile. Capped was measured after stock, with the limits re-applied in between; no Xid, temperatures 51-64 C, needles 3/3 in all four runs.

| | greedy | sampled | decode 60K / 128K / 250K | prefill 60K / 128K / 250K | peak clock / draw |
|---|---|---|---|---|---|
| stock run 1 | 75.1 | 75.3 | 59.2 / 78.4 / 77.8 | 2079 / 2171 / 2207 | 1995 MHz / 341 W |
| stock run 2 | 74.8 | 75.9 | 60.3 / 75.2 / 71.1 | 2070 / 2164 / 2214 | 1995 MHz / 343 W |
| capped run 1 | 67.7 | 69.1 | 56.8 / 64.1 / 70.2 | 1947 / 2016 / 2026 | 1500 MHz / 209 W |
| capped run 2 | 66.0 | 69.0 | 58.5 / 68.8 / 62.1 | 1960 / 2001 / 2024 | 1500 MHz / 209 W |
| **stock vs capped (means)** | **+12%** | **+9.5%** | +4% / +16% / +13% | +6% / +8% / +9% | |

Short-turn decode and prefill gains are consistent across runs. Deep decode single samples vary by +-5% or more (250K ran 77.8 and 71.1 on the same settings), so read those three percentages as "positive, size uncertain". Peak draw is the highest single-card sample; the peak clock and draw columns are taken from the harness's 5-second samples.

## UD-Q4_K_XL, capped, with the other modes (2026-10-05)

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

- One machine, one driver. Single deep-decode samples vary by about +-5%.
- The engine is not bit-repeatable across restarts, so exact-match checks against stock Strata were not possible.
- Not measured: the pinned split (needs ~135 GiB), other GPU counts, cards with less than 24 GB, AMD (upstream says the Q4_K / Q5_K prompt kernels are NVIDIA-only), vision, a 250K-token park.
- Numbers come from a private harness (pi agent turns plus probe scripts) that is not in this repo; `tests/tool-choice-probes.py` is the only script shipped. A reproducible benchmark script is a good first contribution.
