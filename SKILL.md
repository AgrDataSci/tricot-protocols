---
name: tricot-protocols
description: Use when asked how to set up, run or survey a tricot or ClimMob on-farm trial, which questions, traits or data collection moments tricot uses for a crop or crop group, what plot size or materials a trial needs, or which standard operating procedure (SOP) or ClimMob template to use.
---

# Tricot protocols

<!-- version:start -->Skill updated 2026-11-03. 19 protocols in the registry, 2 with question lists (sorghum, sweet potato).<!-- version:end -->

Standard operating procedures (SOPs) for tricot on-farm trials, developed by Bioversity International with national and CGIAR partners. Each SOP is generated from a ClimMob project template, so the questions in the SOP are the questions farmers answer. Use this skill to tell the user which protocol fits their trial and which questions it asks, and to point them to the template and the citable SOP.

The evidence behind the protocols lives in [tricot-knowledge-base](https://github.com/AgrDataSci/tricot-knowledge-base). The data they produced live in [tricot-data](https://github.com/AgrDataSci/tricot-data). The suite entry point is [ai-ready-documentation](https://github.com/AgrDataSci/ai-ready-documentation).

## Use the live files

Protocols change as templates are revised. Read the files you need from `https://raw.githubusercontent.com/AgrDataSci/tricot-protocols/main/`. If that address is blocked, try `https://github.com/AgrDataSci/tricot-protocols/blob/main/<file>`. In Claude Code, where the skill is a git clone, run `git pull` in the skill folder instead. If you cannot reach the repository, say so in one short line and use the installed files.

## Index

| File | What it holds |
|---|---|
| `protocols.csv` | Registry, one row per protocol, with crop, crop group, use case, region, status, ClimMob template and DOI |
| `data/crops.csv` | Crop names, aliases and scientific names, with their crop group and own protocol |
| `data/crop-groups.csv` | Crop groups and the default protocol of each |
| `protocols/<protocol_id>/questions-<lang>.csv` | The questions of the protocol, by data collection moment, in each language |
| `protocols/<protocol_id>/README.md` | Protocol card with status, languages, DOI and purpose |
| `protocols/<protocol_id>/protocol-metadata.xlsx` | Plot size, planting material, authors and funders |
| `protocols/<protocol_id>/sop/` | The rendered SOP documents, `<protocol_id>-sop-<lang>.docx` |

Question files have the columns `form` (the data collection moment), `question_id` (the ClimMob question ID), `question_name`, `question_type` and `question_desc`. A `ranked trait` is a question farmers answer by ranking the three options, and its description gives the positive and the negative statement. A `question` is any other question.

## Find the protocol for a crop

Resolve the crop in this order and stop at the first level that answers.

1. **The crop's own protocol.** Look up the crop in `data/crops.csv` by name, alias or scientific name. If it has a `protocol_id`, use it.
2. **The crop group.** If the crop has no protocol of its own, use the `default_protocol_id` of its `crop_group` in `data/crop-groups.csv`. Groups are cereals, small grains, legumes, roots tubers and bananas (rtb), leafy vegetables and forages.
3. **The core protocol.** If the crop is in no group, use `core`, the protocol for on-farm trials without a defined crop.

Then check `protocols.csv` for every protocol of that crop or group, and pick by context.

- `variety-testing` is the full SOP for on-farm variety testing and the default.
- `seed-systems` is a shorter survey for seed system projects. Use it when the user works on seed systems or needs a light survey.
- `breeding` follows a breeding pipeline.
- A protocol with a `region` (west-africa, tropics, nordic) fits that region better than the global one.

Always tell the user which level answered. For example, "tricot has no teff protocol, so this comes from the small grains protocol, written for finger and pearl millet". Name the crop the protocol was written for, and say which questions may need adapting, such as crop-specific traits, plot size and planting material.

## Answer which questions a protocol uses

1. Check the `status` of the protocol in `protocols.csv`.
   - `published` or `rendered` means its question files exist. Read `questions-en.csv`, or the user's language when it is listed.
   - `placeholder` means the ClimMob template exists but its questions are not yet published here. Say so, give the ClimMob template name and code, and offer the questions of the nearest protocol with question files, preferring the same crop group. Label them clearly as coming from another crop.
2. Group the questions by `form`, in the order of the file. The forms are the data collection moments, from registration to harvest and the socio-economic baseline.
3. Separate ranked traits from other questions when the user asks about traits.
4. Quote question names and statements as they appear in the file. Never invent a question, trait, plot size or data collection moment.

## Boundaries

- The protocols say how the team runs trials. They do not prove a trait or design is right for the user's target environment. Point to the knowledge base for the evidence.
- Do not merge questions from several protocols into one list without saying where each comes from.
- Plot size and planting material are crop-specific. Read them from `protocol-metadata.xlsx` and never carry them across crops.
- When the user wants to run a trial, point them to the ClimMob template named in `protocols.csv` and to [ClimMob](https://climmob.net). ClimMob also supports AI voice data collection in local languages through Sikia.
- For how to analyse the data a protocol produces, use [tricot-analysis-workflows](https://github.com/AgrDataSci/tricot-analysis-workflows).

## Cite

Cite each SOP by its concept DOI in `protocols.csv`. A protocol without a DOI is cited through the collection, Cremaschi A, Laporte M-A, Manners R, Nyirahabimana H, de Sousa K (2026). Standard operating procedures for citizen science experiments using the tricot approach. [doi:10.5281/zenodo.18428279](https://doi.org/10.5281/zenodo.18428279). Credit the authors listed in the protocol's metadata, for example "following the sweet potato SOP by the International Potato Center and Bioversity International".
