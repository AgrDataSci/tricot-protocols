<!-- badges: start -->
[![License](https://img.shields.io/badge/License-CC%20BY%204.0-blue.svg)](https://creativecommons.org/licenses/by/4.0/deed.en) 
[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.15224389.svg)](https://doi.org/10.5281/zenodo.15224389)
<!-- badges: end --> 

## Standard operating procedures for citizen science experiments using the tricot approach
> Almendra Cremaschi, Marie-Angélique Laporte, Kauê de Sousa


# Tricot Protocols

This repository provides **standard operating procedures (SOPs)**, survey tools, and trait metadata for implementing **tricot** (Triadic Comparison of Technologies) on-farm trials. It is designed to support data collection, analysis, and reuse in a **FAIR** (Findable, Accessible, Interoperable, Reusable) and multilingual way.

The repository uses a **project-oriented structure**, allowing for efficient management of core methods shared across crops while maintaining crop-specific protocols and translations.

## What is tricot?

Tricot is a participatory research approach where farmers test and compare three crop varieties (or technologies) on their own farms. It supports decentralized experimentation and citizen science while generating valuable data for breeding programs and food system actors. More at [https://climmob.net](https://climmob.net)

---

## Repository structure

The project follows a project-oriented layout inspired by best practices in the R community.

```text
tricot-onfarm-sop/
├── README.md
├── LICENSE
├── core/
│   ├── methodology.md
│   ├── core_traits.csv
│   └── metadata/crop-ontology-links.md
├── crops/
│   ├── amaranth/
│   │   ├── en/leafy_amaranth_sop.md
│   │   ├── fr/leafy_amaranth_sop.md
│   │   └── pt/leafy_amaranth_sop.md
│   ├── cassava/
│   │   └── ...
│   ├── cowpea/
│   │   └── ...
```

---

## Contribute

This template is open for improvement! You can:
- Suggest edits via GitHub Issues
- Fork the repository for your own project
- Contribute back improvements via pull request

---

## References

- [FAIR Principles](https://www.go-fair.org/fair-principles/)
- [DataCite Metadata Schema](https://schema.datacite.org/)