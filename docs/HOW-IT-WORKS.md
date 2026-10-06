# How the resident split works

Background: Strata's routed experts live in three places. A per-card **expert cache** in VRAM holds the hottest ones; the rest are read from the GGUF shards. Upstream has three ways to serve the rest:

| Mode | Where the non-cached experts live | RAM cost for Q4_K_XL |
|---|---|---|
| pinned split (upstream) | all 77 GB page-locked, plus the OS file cache while loading | ~135 GiB |
| `--mmap-experts` | the OS file cache, on demand | what the OS keeps (it evicts under pressure) |
| **`--resident-experts` + layer split (this repo)** | **only the experts no card holds** are page-locked: 38 GiB | ~38 GiB |

Upstream's `--resident-experts` already did the third thing for one GPU, but with a layer split it either refused or silently fell back to mmap mode (the `WARNING ... does not support a layer split yet` branch the patch removes). The patch does three things:

1. **Leave every stage's cache out of the RAM copy.** `pin_cache_complement` is given the (layer, expert) pairs held by each later stage's cache, not only CUDA0's, so RAM holds exactly the complement of all caches.
2. **Copy evicted experts back from the right card.** The adaptive tier swaps hot experts into the caches while serving. In the resident mode an evicted expert must be copied back into the RAM copy first. The slot numbers in `host_res` belong to whichever cache owns the layer, so the copy must read *that* card's cache on *that* card's stream. The first version read CUDA0's cache for every layer, which copied another expert's bytes into RAM; after the first adaptive swaps some experts then computed from the wrong weights and the output turned to garbage. `resident_stage_swaps` now takes a `locate(layer)` callback returning the owning cache, stream and device (`struct SwapHome`), and synchronizes every stream it used.
3. **Say why a copy fails.** Each `cudaMemcpyAsync` / sync / `stage_exchange` failure now logs the layer, slot and device instead of returning a bare `false`.

The serve path and the non-serve (`generate`) path are both covered. The serve path needed the callback by hand because upstream added a `pin_blobs` block after the call in 0.1.39.

## Porting to other Strata versions

The patch is against exactly the `v0.1.39` tree (`27b0e86`) and `build.sh` applies it with `patch -F0` (no fuzz). On 0.1.38 and 0.1.39 the context moved enough that fuzzy application put a hunk into the wrong class and **still compiled**. If you port it to a newer Strata, apply with `-F0`, read every hunk, and check the startup log for the line reporting the page-locked complement (`21.59 GiB` for IQ4 and `38.03 GiB` for Q4_K_XL on the reference box) and for the absence of the mmap-fallback warning.

## What `tool-choice` does

`serve/frontend.py: apply_tool_choice` maps a request's `tool_choice` to (tools handed to the chat template, forced prefix):

- `none`: the tools are left out of the prompt, so the model cannot call one.
- `required` / `any` / a named function: the answer is made to start inside a call (`<tool_call>\n<function`, plus the name when one tool is forced) and the model writes the rest. The prompt is rendered without thinking. There is no constrained decoding; the arguments are the model's.
- Bad input (a forced call without tools, an unknown name) is a 400.

`tests/tool-choice-probes.py` exercises all of these plus a streamed forced call.
