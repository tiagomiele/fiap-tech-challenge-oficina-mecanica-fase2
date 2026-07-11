# Diagramas de Arquitetura

Coleção de diagramas da aplicação. Cada diagrama tem o **PNG** (para visualização) e o **fonte versionável** (para edição).

| Diagrama | PNG | Fonte | Ferramenta |
|---|---|---|---|
| C4 — Nível 1 (Contexto) | `oficina-c4-nivel1.png` | `oficina-c4-nivel1.puml` | PlantUML + C4-PlantUML |
| C4 — Nível 2 (Contêiner) | `oficina-c4-nivel2.png` | `oficina-c4-nivel2.puml` | PlantUML + C4-PlantUML |
| C4 — Nível 3 (Componente) | `oficina-c4-nivel3.png` | `oficina-c4-nivel3.puml` | PlantUML + C4-PlantUML |
| Arquitetura lúdica (detalhada) | `oficina-arquitetura-ludica.png` | `oficina_arquitetura_ludica.py` | diagrams (mingrammer) |
| Arquitetura (alto nível) | `oficina-arquitetura-altonivel.png` | `oficina_arquitetura_altonivel.py` | diagrams (mingrammer) |
| Clean Architecture (4 anéis) | `oficina-clean-arch-aneis.png` | `oficina_clean_arch_aneis.py` | matplotlib |
| Infraestrutura AWS | `oficina-infra-aws.png` | `oficina_infra_aws.py` | diagrams (mingrammer) |
| Fluxo de Deploy (CI/CD) | `oficina-fluxo-cicd.png` | `oficina_fluxo_cicd.py` | diagrams (mingrammer) |
| Processo (value stream) | `oficina-processo.png` | `oficina-processo.dot` | Graphviz |

## Como regenerar

- **PlantUML** (`.puml`): `plantuml oficina-c4-nivel1.puml` (requer Java + `plantuml.jar`).
- **diagrams** (`.py`): `pip install diagrams` + Graphviz; então `python oficina_infra_aws.py`.
- **matplotlib** (`.py`): `pip install matplotlib`; então `python oficina_clean_arch_aneis.py`.
- **Graphviz** (`.dot`): `dot -Tpng oficina-processo.dot -o oficina-processo.png`.

> Notas de fidelidade ao código: o registry real é **GHCR** (`ghcr.io`, ver `.github/workflows/cd.yml`); o transporte externo é **HTTP** (Service K8s na porta 80); e o e-mail usa **Mailtrap (SMTP)** como sandbox.
