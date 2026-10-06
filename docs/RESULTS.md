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

## Stock Strata v0.1.40.1 against this repo's patched v0.1.39 (2026-10-06, capped)

Upstream v0.1.40 includes the resident split with a layer split (#848) and `tool_choice`. Stock v0.1.40.1 (unpatched, built from the `v0.1.40.1` tag with a local CUDA base image) was run with the same Q4_K_XL resident config as above, capped (220 W / 1500 MHz / UV profile), two runs, the same afternoon as the patched capped runs. No Xid, temperatures 54-56 C, needles 3/3 in both runs.

| | greedy | sampled | decode 60K / 128K / 250K | prefill 60K / 128K / 250K |
|---|---|---|---|---|
| stock v0.1.40.1 run 1 | 68.9 | 73.0 | 59.5 / 66.1 / 65.8 | 1950 / 2123 / 2067 |
| stock v0.1.40.1 run 2 | 67.8 | 69.4 | 57.2 / 67.2 / 66.8 | 1922 / 2112 / 2072 |
| patched v0.1.39 run 1 | 67.7 | 69.1 | 56.8 / 64.1 / 70.2 | 1947 / 2016 / 2026 |
| patched v0.1.39 run 2 | 66.0 | 69.0 | 58.5 / 68.8 / 62.1 | 1960 / 2001 / 2024 |
| **v0.1.40.1 vs v0.1.39 (means)** | +2% | +3% | +1% / +0.3% / +0.2% | -1% / +5% / +2% |

A tie within noise: the two stock sampled runs differ by 3.6 tok/s among themselves, more than the means differ. Other work on the box during the runs could have contributed. The config in [config/](../config/strata-ud-q4_k_xl-resident-park.json) ran unchanged on v0.1.40.1.

**`tool_choice` probes on stock v0.1.40.1** (`tests/tool-choice-probes.py`, 5 tries per case): passed `none`, a named function (5/5 against the grain), `auto` both ways and Anthropic `any`. Failed or partial: `required` with an unrelated prompt 0/5 (no call), `required` with a related prompt 3/5, streamed `required` 4/5, and no HTTP 400 for an unknown tool name or for `required` without tools.
- The two 400 cases are by design upstream: its `forced_call` logs a bad value and acts as `auto` ("a client's odd choice must not stop its request"). The patch in this repo returns 400.
- The `required` failures were the probe's token budget, not a missing feature. Upstream writes the forced call's opening only after thinking ends, and the probe allowed 400 tokens, so a model that thinks first can run out (`finish_reason: length`). Rerun on the same stock build, 3 tries per case (unrelated prompt, related prompt, streamed): **400 tokens, default thinking 8/9** (the one miss ended in `length`); **4,000 tokens 9/9**; **400 tokens with `reasoning_effort: "none"` 9/9**. So `required` works on stock v0.1.40.1 when the budget allows or thinking is off; the first run's 7 of 15 on these cases was the same budget effect and varies run to run.
- For comparison, every probe passed on the patched v0.1.39 build on 2026-10-05. That build renders forced calls without thinking, so it did not hit the budget limit.

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
