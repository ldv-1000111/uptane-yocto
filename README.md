# Uptane OTA Implementation Guide — Documentation

This repository contains the **ReadTheDocs source** for the complete
Uptane OTA Implementation Guide (Steps 1–24, single consolidated tutorial).

Hosted at: https://uptane-ota-implementation-guide.readthedocs.io

## Quick Start — Local HTML Build

```bash
cd docs
pip install -r requirements.txt
make html
# → open build/html/index.html
```

Or with live reload:

```bash
make livehtml
# → opens http://localhost:8000 and rebuilds on every file save
```

## Uploading to ReadTheDocs

1. Push this repository to GitHub
2. Go to https://readthedocs.org → Import a Project → connect your repo
3. ReadTheDocs reads `.readthedocs.yaml` at the root and runs:
   ```
   pip install -r docs/requirements.txt
   sphinx-build -M html docs/source docs/build
   ```
4. Your docs are live at `https://<your-project>.readthedocs.io`

## Structure

```
uptane-yocto/
├── .readthedocs.yaml          ← ReadTheDocs build config
├── docs/
│   ├── Makefile               ← local build
│   ├── requirements.txt       ← Sphinx dependencies
│   └── source/
│       ├── conf.py            ← Sphinx configuration
│       ├── index.rst          ← master TOC
│       ├── _static/
│       │   └── custom.css
│       ├── overview/
│       ├── phase1_environment/
│       ├── phase2_yocto/
│       ├── phase3_cpp/
│       ├── phase4_testing/
│       ├── phase5_hardening/
│       ├── phase6_cicd/
│       ├── phase7_security/
│       ├── phase8_deployment/
│       └── appendices/
└── README.md
```

## Content Map

| Phase | Steps | Topic |
|---|---|---|
| 1 | 1 | Host environment setup |
| 2 | 2–5 | Yocto layer, machine config, WIC layout, BitBake build |
| 3 | 6–12 | C++ OTA client: CMake, metadata, verifier, downloader, A/B, UDS, orchestrator |
| 4 | 13–15 | Unit tests, mock backend, QEMU integration |
| 5 | 16–18 | Secure boot, TLS/mTLS, ECU manifest + anti-rollback |
| 6 | 19–20 | GitHub Actions CI/CD, campaign management |
| 7 | 21–22 | Threat model (TARA), penetration testing |
| 8 | 23–24 | Production checklist (R156 + 21434), day-2 operations |
| Appendices | A–E | Key ceremony, sw-description, Yocto vars, config ref, troubleshooting |
