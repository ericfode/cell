# Terminal-Bench evolution evidence

Cell-zero/2 was exercised with Harbor 0.22.0 on the `headless-terminal` Terminal-Bench task using Docker 29.3.1 on arm64 and local Codex 0.144.6 with `gpt-5.6-sol`.

Task checksum: `0f08b1ccc560ac08b8420b4a493a3b4c5354e2ace9f0cbe63a44e861e46c780d`

| Run | Harbor job | Trial | Capsule root | Reward |
| --- | --- | --- | --- | ---: |
| Oracle platform smoke | `20cb5617-7e65-4bdf-a2b2-93d0ff716a48` | `81eac431-28cc-407f-9de0-31eb581c5857` | n/a | 1.0 |
| Parent | `0dac0665-9f3f-4d0b-b18b-2504414d8a5a` | `efc5b3f4-39c7-406b-b4d9-6bcba2a3d2be` | `F0CE01681A13B2D6870B6AC02BCA442EF9C73DAFDBA7B3CDC7DE56B72CDC3462` | 0.0 |
| Candidate 1 | `b0b670c2-56aa-4d7b-b8d8-e0cb0ff6c4b6` | `4d8ed51a-a806-4dae-906a-c49327092763` | `090EDA926B2B960F7AD493AE712977329D066E7757BFFD8EA6CAD1144387609E` | 0.0 |
| Trace-informed candidate 2 | `9ebc800d-8d4b-4d17-8594-9c8eab873053` | `02dafa55-8f24-40b4-831c-a43b5a761f9d` | `C6DE8E06BBA4C54C6718EF0FA8BA7B0F4EE6CA631D62FFB46E1E8FC03C9D3734` | 0.0 |

All Cell-zero/2 runs carried evaluator root `E4A718F09A3C772009CB66283FD2AFD078F77D3AEEADE86635C54644A7571624` and step root `01C611EF97FF359D25F8C5B98FFFFCF0EA2258DC5195C770389CB6E23DEAB96F`.

Candidate 2 incorporated the first candidate trace's failure mode by requiring short, separate verification commands and a PTY-backed implementation. It did not improve the reward. The strict hereditary policy rejected the tie and retained the parent. `harbor-evolution.sexp` records the paired rewards and `:retain` decision. `selected-capsule.sexp` is the complete retained capsule after recording evolution history and clearing transient trial state, so its content hash differs from the original parent root.

The raw `harbor-runs/` trees are intentionally ignored because they contain bulky trajectories and machine-local paths.
