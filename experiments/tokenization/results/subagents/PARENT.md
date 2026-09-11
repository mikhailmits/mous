# Parent / monarch notes

Subagents (do not wait in-process; loop tick integrates):

- spaces: bc-deabe02c-21b0-5ade-b0a9-13a386d68946
- languages: bc-71785285-2dad-5b75-97a3-434633ef132e
- compress: bc-3dc96667-4d81-56d1-89fd-d348b02a4cea
- images: bc-5745c9cd-cc28-574b-a925-6ca691ba04e6
- dsl: bc-668c18dc-f3eb-5b2a-991e-3472feb13eac

Current fair text leader: `tiny_ledger_vm` 5123 / `group_cat_name_daynum` 5125 GPT-5 tokens (yaml_like 12020 is the old baseline).
Vision bound: 765 high-detail tiles for a native 4-col 512×2048 ledger (`img_4col_1bit`); tall PNG is the same cost but crushed.
Cheat/tool bound: slim `tool_views` ~651 with Qwen 1.0; `aggregates_only` 709 with 0.83 because discretionary_share was misread as a percent.

Loop name: `loop-tokenization-lab`
