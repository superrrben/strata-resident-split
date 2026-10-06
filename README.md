# strata-resident-split: Qwen Flash Next Q4_K_XL - dual 3090's, 96gb ram, 75 tps decode with 33gb ram free. 

Run **Qwen3.8-Flash-Next at Unsloth UD-Q4_K_XL** on [Strata](https://github.com/Niko1221/Strata) across **2x3090's and ~92 GB of RAM**, instead of the ~135 GB of RAM upstream's layer-split mode needs.

This is a small patch set on top of Strata v0.1.39 (`6f32ec0`), not a fork. Strata is MIT-licensed work by Niko1221 and contributors; all the engine credit is theirs.

**What this adds over stock Strata:** Q4_K_XL runs in ~92 GiB of RAM instead of ~135 GiB (33 GiB stays free), about 1.5x the speed of the only mode that fits at that size on the same box (stock mmap: 45 to 67 tok/s greedy capped, 75 at stock power), and a working `tool_choice` (`none` / `required` / a named function), plus a pinned build, prep scripts and compose file with every measurement and caveat published.

## My goal

Q4 has about half the KLD divergence score of IQ4. Many strata build use IQ2 and IQ3. I personally do not trust these smaller quants for long horizon taks, even though they are perfectly servicable for most situations. My 96gb setup had me deeply regretting not getting 128gb ram, but with the awesome work done on Strata, Claude was able to help getting this Q4 setup to a mature spot with performance fit for daily driving. 

## The setup

Q4_K_XL has 71.7 GiB of routed experts. Two RTX 3090s hold about 34 GiB of them. Upstream's layer split then loads **all** 77 GB of experts into pinned RAM and lets the OS file cache pass the files through while it loads, which upstream's docs size at ~135 GB of RAM. Without the split (mmap mode) the same box decodes at 45 tok/s.

## What the patches do

| Patch | What |
|---|---|
| [`patches/resident-split-0.1.39.patch`](patches/resident-split-0.1.39.patch) | Makes `--resident-experts` work **with a layer split**. Only the experts *no card holds* (38 GiB here) are page-locked in RAM; adaptive expert swaps copy an evicted expert back from the card that owns its layer. C++, one file (`src/program/generate.cpp`). Details: [docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md). |
| [`patches/tool-choice-0.1.39.patch`](patches/tool-choice-0.1.39.patch) | `tool_choice` (`none` / `required` / a named function; OpenAI and Anthropic shapes) in the Python server. Upstream ignores the field. No constrained decoding: a forced call forces the prefix, the arguments are the model's. Also: an explicit `temperature: 0` stays greedy when the config has sampler defaults. Independent of the first patch. |

## Measured

One machine: 2x RTX 3090 (24 GB), 92 GiB RAM, both cards PCIe x8. Two runs per row, same day, same image and config. "Capped" is the author's everyday setting (220 W power cap, 1500 MHz clock lock, undervolt profile); "stock" is the cards' default limits (390 W / 350 W, no clock lock). Full table, methods and caveats: [docs/RESULTS.md](docs/RESULTS.md).

| UD-Q4_K_XL, 262K context, MTP draft on | greedy tok/s | sampled tok/s | prefill at 60-250K | RAM left free |
|---|---:|---:|---:|---:|
| **this repo, resident split, stock power** | **75.1 / 74.8** | **75.3 / 75.9** | 2,070-2,214 tok/s | **33 GiB** |
| this repo, resident split, capped 220 W / 1500 MHz | 67.7 / 66.0 | 69.1 / 69.0 | 1,947-2,026 tok/s | 33 GiB |
| stock mmap mode, capped (previous day) | 45.5 | 51.6 | ~1,600 tok/s | 72 GiB |
| upstream split, pinned (**not run here**: needs ~135 GiB) | - | - | - | - |

Stock power is about 12% faster on greedy decode and 9% on sampled for roughly 60% more board power (peak 1,995 MHz / 343 W against 1,500 MHz / 209 W). The cap is a choice for heat and stability, not something this repo needs.

Upstream reports 64-78 tok/s for the pinned split on a 165 GiB box ([their docs/UNSLOTH_Q4.md](https://github.com/Niko1221/Strata/blob/v0.1.39/docs/UNSLOTH_Q4.md)). That is a different machine, so read it as "same ballpark", not a comparison.

## Requirements

- Linux, NVIDIA driver >= 580, Docker with the NVIDIA container toolkit
- Two NVIDIA GPUs (tested: 2x RTX 3090). Other cards should work but are untested.
- ~92 GiB RAM or more. At 92 GiB, 33 GiB stays free with the model running and ~26 GiB with large parked conversations. Much less will swap.
- ~115 GB disk for the GGUF, ~7 GB for the pack and draft layer
- This is **experimental** upstream (UD-Q4_K_XL) and experimental here. Read "Known limits" below.

## Quick start

```bash
git clone https://github.com/superrrben/strata-resident-split && cd strata-resident-split

# 1. build the patched image (clones upstream at 6f32ec0, applies the patches, compiles ~minutes on every core)
CUDA_ARCHITECTURES=86 ./build.sh          # 86 = RTX 30xx, 89 = RTX 40xx, 120 = RTX 50xx
#    CHECK=1 ./build.sh only verifies that the patches apply

# 2. download UD-Q4_K_XL (4 shards, revision 38bb39e) into $MODELS/Qwen3.8-Flash-Next-UD-Q4_K_XL/UD-Q4_K_XL/
#    and check the SHA-256s listed in upstream's docs/UNSLOTH_Q4.md

# 3. one-time prep: pack + MTP draft layer + config
export MODELS=/path/to/models DATA=/path/to/strata-data
./prep.sh

# 4. serve (OpenAI + Anthropic compatible API on 127.0.0.1:8080; load takes ~45 s)
docker compose up -d
curl -s localhost:8080/health
```

Optional check of the `tool_choice` patch: `URL=http://127.0.0.1:8080 N=5 tests/tool-choice-probes.py`.

The shipped config ([`config/`](config/strata-ud-q4_k_xl-resident-park.json)): both GPUs with `layer_split: auto`, `--resident-experts`, 262,144 context with an int8 KV cache, MTP draft (`--spec 4`), `--pcie-frac 0`, and upstream's conversation parking (12 GiB, 6 slots) so sub-agents and alternating conversations restore from RAM instead of re-reading their prompt (details below). Sampling defaults are temperature 1.0 / top_p 0.95 / top_k 20.

## Context size and multiple conversations

**Context.** The shipped config allows up to **262,144 tokens** per conversation (int8 KV cache, the newest 32K of KV kept resident on the GPUs). Measured on the reference machine at stock power:

| Prompt size | Prefill | Time to read the prompt | Decode afterwards |
|---:|---:|---:|---:|
| 60K tokens | ~2,075 tok/s | ~33 s | 59-60 tok/s |
| 128K tokens | ~2,170 tok/s | ~63 s | 75-78 tok/s |
| 250K tokens | ~2,210 tok/s | ~117 s | 71-78 tok/s |

Needle retrieval was checked at 128K (3 of 3). It was not checked at 250K on Q4_K_XL, so treat the top of the window as unverified recall. Lower `--max-context` in the config if you want to trade the window for VRAM headroom.

**Multiple conversations.** One conversation generates at a time, but several can stay open and you can switch between them quickly. This is **upstream's** conversation parking (Strata 0.1.39), not something this repo adds; what the resident split adds is the RAM to hold it, because the pinned split needs ~135 GiB before any parking cache. The config enables it: up to **6 conversations** are kept in a **12 GiB** RAM cache, and switching between them restores the parked state instead of re-reading the prompt.

- With a 145K-token parent and two 66K-token sub-agents taking turns, none of the 9 later turns had to re-read its history. Later rounds took 2.3-3.3 s, and about 26 GiB of RAM stayed free with all three parked.
- Answers after a restore matched a no-switching control in every check (6 of 6 short, 3 of 3 at 127K).
- Each separate conversation takes a slot, including one-off scripts and web-UI chats. A seventh evicts the least recently used one, which costs a re-read, not an error. Roughly three conversations near 128K fill a 12 GiB cache.
- Parallel generation (`--batch N`) works but is **not** enabled: on two cards it gave no extra throughput (slots carry no MTP draft, so 4 streams ran at 17-40 tok/s each, about what one stream does alone) and cost 8-17 GiB of RAM plus 4-8% solo speed. These batch figures are from the IQ4 build of the same engine, not re-run on Q4_K_XL.
- To hold more or larger parked conversations, raise `--conversation-cache-mib` and `--conversation-cache-slots` in the config, and watch your free RAM.
- The server ignores the `model` name in requests, so a client pointed at the wrong model name will still get this model.

## Known limits

- **Tested on one machine.** Other GPU counts, VRAM sizes and RAM sizes are unmeasured. If the whole complement does not fit in RAM, upstream's `#467` path keeps the hottest experts and reads the rest from the GGUF.
- **Not bit-repeatable.** The engine does not produce identical output across restarts, so "same tokens as stock" could not be checked. Checked instead: needle retrieval 3/3 at 128K, parked-and-restored conversations answer identically to a no-switching control (6/6, and 3/3 at 127K), and a repeated-run quality pack gave no sign of damage (a private pack, +-4 noise, so a hint and not a result).
- **`allowed_hosts: "*"`** in the config turns off the server's Host-header check. The compose file binds to loopback by default for that reason; the server has no API key. Do not expose it to a network you do not trust.
- `tool_choice` forcing has no constrained decoding. It was probed 5 times per case on one model and passed, which is not a guarantee.
- Vision is not built (`BUILD_VISION=0`), and the `/v1/responses` endpoint with `tool_choice` was not tested.
- `build.sh` and `prep.sh` were written for this repo from the scripts used on the original box. The patch application (`CHECK=1`) and the pack step (byte-identical `dense.bin`) were re-run from a clean state; the full docker build and the draft-layer download were not.

## Hardware used
- 2x 3090's pcie 4.0 x8 (second 3090 connected via a 20cm riser cable)
- 96gb ddr5 6000mhz cl36
- 9950x
- Asus Proart X870E
- Samsung 9100 pro 4tb

## Upstream

These patches are  upstream-friendly: if Strata's maintainers want the resident-split change, it is MIT and they are welcome to it. Please report engine bugs upstream only after reproducing on an unpatched build.

## License

MIT, see [LICENSE](LICENSE). The patches modify Strata (MIT, (c) Niko1221 and the Strata contributors); that notice is kept.
