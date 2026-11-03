<!-- badges: start -->
[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.18428279.svg)](https://doi.org/10.5281/zenodo.18428279)
[![ProjStatus](https://www.repostatus.org/badges/latest/active.svg)](https://www.repostatus.org/#active)
[![Lifecycle](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
[![License](https://img.shields.io/badge/license-CC%20BY%204.0-blue.svg)](https://creativecommons.org/licenses/by/4.0/)
<!-- badges: end --> 

## Standard operating procedures for citizen science experiments using the tricot approach
> Almendra Cremaschi, Marie-Angélique Laporte, Rhys	Manners, Hyacinthe	Nyirahabimana, Kauê de Sousa

# Tricot Protocols

This repository holds the **standard operating procedures (SOPs)** for running **tricot** (Triadic Comparison of Technologies) on-farm trials. Each SOP is generated from a project template on [ClimMob](https://climmob.net), so the document a team reads and the survey farmers answer always match. The SOPs are multilingual and FAIR (Findable, Accessible, Interoperable, Reusable).

tricot-protocols is the protocols layer of the [AI-ready documentation suite](https://github.com/AgrDataSci/ai-ready-documentation). Start there for the full picture. This repository also works on its own.

## What is tricot?

Tricot is a participatory research approach where farmers test and compare three crop varieties (or technologies) on their own farms. It supports decentralized experimentation and citizen science while generating valuable data for breeding programs and food system actors. More at [https://climmob.net](https://climmob.net)

## Who uses it

NARS breeding teams and CGIAR programmes running late-stage on-farm testing, product development teams and seed companies, and anyone planning a tricot trial. The SOPs answer one question. How do I set up, run and survey a tricot trial for this crop?

## Use it with AI

Paste `https://github.com/AgrDataSci/tricot-protocols` into an AI assistant with web access and ask, for example, "which questions does tricot use for cowpea?". The assistant reads [`AGENTS.md`](AGENTS.md) and [`SKILL.md`](SKILL.md). It finds the crop's own protocol, or falls back to its crop group (cereals, small grains, legumes, roots tubers and bananas, leafy vegetables, forages), or to the core protocol, and reads the question list of that protocol. In Claude, upload `SKILL.md` as a skill. To reach every layer of the suite from one link, use [ai-ready-documentation](https://github.com/AgrDataSci/ai-ready-documentation).

## How the repository is organised

```
SKILL.md, AGENTS.md, llms.txt  instructions for AI assistants
version.json                   version and commit, stamped on every push to main
protocols.csv                  registry, one row per protocol, the single source of truth
protocols/<protocol_id>/
  README.md                    protocol card with status, ClimMob template, DOI and languages
  protocol-metadata.xlsx       metadata, crop, authors, funders and plot size
  CHANGELOG.md                 changes between Zenodo versions
  questions-<lang>.csv         questions of the protocol by data collection moment (generated)
  sop/                         rendered SOPs, <protocol_id>-sop-<lang>.docx
  logs/<version>/              ClimMob survey, clean question list and session info of each render
  zenodo-metadata.json         DataCite metadata of the standalone record (generated)
data/                          text and figures shared by every SOP
  crops.csv                    crops, aliases, scientific names, crop group and own protocol
  crop-groups.csv              crop groups and their default protocol
metadata/                      metadata of the collection record
script/                        rendering and metadata scripts
docs/                          paper describing the repository
```

Protocol IDs follow `<crop>-<use case>[-<region>]`. The use cases are

- `variety-testing`, the full SOP for on-farm variety testing
- `seed-systems`, a shorter survey for seed system projects
- `breeding`, on-farm variety testing designed around a breeding pipeline
- `core`, on-farm trials without a defined crop

## Protocols

| Protocol | ClimMob template | Status | DOI |
|---|---|---|---|
| [sweetpotato-breeding](protocols/sweetpotato-breeding) | `sweetpotat` | published | [10.5281/zenodo.20525269](https://doi.org/10.5281/zenodo.20525269) |
| [sorghum-variety-testing](protocols/sorghum-variety-testing) | `sorghum` | rendered | |
| [amaranth-variety-testing](protocols/amaranth-variety-testing) (leafy amaranth) | `amarantemp` | placeholder | |
| [bean-variety-testing](protocols/bean-variety-testing) | `beantempl` | placeholder | |
| [cassava-variety-testing](protocols/cassava-variety-testing) | `cassavtemp` | placeholder | |
| [cassava-variety-testing-west-africa](protocols/cassava-variety-testing-west-africa) | `casstempWA` | placeholder | |
| [cowpea-variety-testing](protocols/cowpea-variety-testing) | `cowpea` | placeholder | |
| [forages-variety-testing-nordic](protocols/forages-variety-testing-nordic) | `foragenort` | placeholder | |
| [forages-variety-testing-tropics](protocols/forages-variety-testing-tropics) | `foragetemp` | placeholder | |
| [groundnut-variety-testing](protocols/groundnut-variety-testing) | `groundnut` | placeholder | |
| [maize-variety-testing](protocols/maize-variety-testing) | `maizetempl` | placeholder | |
| [millet-variety-testing](protocols/millet-variety-testing) (finger, pearl and other small grains) | `millet` | placeholder | |
| [pigeonpea-variety-testing](protocols/pigeonpea-variety-testing) | `pigeonpea` | placeholder | |
| [potato-variety-testing](protocols/potato-variety-testing) | `potato` | placeholder | |
| [bean-seed-systems](protocols/bean-seed-systems) | `beanshort` | placeholder | |
| [maize-seed-systems](protocols/maize-seed-systems) | `maizeshort` | placeholder | |
| [potato-seed-systems](protocols/potato-seed-systems) | `potatshort` | placeholder | |
| [rice-seed-systems](protocols/rice-seed-systems) | `riceshort` | placeholder | |
| [core](protocols/core) | `CoreTemp` | placeholder | |

Status moves from `placeholder` (folder ready, metadata to fill) to `rendered` (SOPs generated and under review) to `published` (standalone Zenodo record with a DOI).

## Publishing on Zenodo

Every protocol is a standalone Zenodo record with its own DOI, holding the SOP in all its languages. The repository itself is the collection record, [10.5281/zenodo.18428279](https://doi.org/10.5281/zenodo.18428279). The two are linked both ways.

1. Fill `protocol-metadata.xlsx` and render the SOP with `script/01-render-protocols.R`.
2. Run `script/helper/helper-03-parse-protocol-metadata-as-json.R` to write `zenodo-metadata.json`. It adds `IsPartOf` the collection.
3. Upload the PDFs as a new record, or a new version of the existing record, using that metadata.
4. Add the concept DOI (all versions) to `protocols.csv` and set the status to `published`.
5. Run `script/helper/helper-02-parse-metadata-as-json.R`. It lists every published protocol as `HasPart` of the collection for its next release.

Always cite the concept DOI, never a version DOI.

## Adding a protocol

1. Create the project template on ClimMob.
2. Add a row to `protocols.csv` with the template code, and link the crop in `data/crops.csv`.
3. Copy a placeholder folder from `protocols/` and rename it to the new protocol ID.
4. Follow the steps under Publishing on Zenodo.

## Contribute

You can suggest edits via GitHub Issues, fork the repository for your own project, or contribute improvements via pull request.

## References

- [FAIR Principles](https://www.go-fair.org/fair-principles/)
- [DataCite Metadata Schema](https://schema.datacite.org/)

## License

Protocols and documentation are released under [CC BY 4.0](LICENSE), with rights held by the International Plant Genetic Resources Institute (Bioversity International).
