import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Circle, FancyArrowPatch

fig, ax = plt.subplots(figsize=(12, 12))
ax.set_xlim(-7.2, 7.2)
ax.set_ylim(-7.6, 7.6)
ax.set_aspect("equal")
ax.axis("off")

# Aneis (do externo para o interno) - cores
rings = [
    (6.6, "#1B3A57"),  # infrastructure - azul escuro
    (5.1, "#2E6E8E"),  # adapter - azul medio
    (3.6, "#4FA3A5"),  # usecase - verde-agua
    (2.1, "#8BC34A"),  # domain - verde
]
for r, c in rings:
    ax.add_patch(Circle((0, 0), r, facecolor=c, edgecolor="white", linewidth=3, zorder=1))

txt = dict(ha="center", va="center", zorder=5, color="white")

# 4 - INFRASTRUCTURE (banda externa, topo)
ax.text(0, 6.05, "4 - INFRASTRUCTURE", fontsize=17, fontweight="bold", **txt)
ax.text(0, 5.55, "anel externo - composition root", fontsize=10, style="italic", **txt)
ax.text(0, 5.15, "SecurityConfig  -  AdminBootstrap  -  OpenApiConfig", fontsize=10.5, **txt)

# 3 - ADAPTER
ax.text(0, 4.55, "3 - ADAPTER", fontsize=16, fontweight="bold", **txt)
ax.text(0, 4.10, "interface adapters", fontsize=9.5, style="italic", **txt)
ax.text(0, 3.72, "Controllers  -  DTOs  -  JPA Repositories  -  JWT  -  Notification", fontsize=10, **txt)

# 2 - USECASE
ax.text(0, 3.10, "2 - USECASE", fontsize=15, fontweight="bold", **txt)
ax.text(0, 2.68, "application business rules", fontsize=9, style="italic", **txt)
ax.text(0, 2.34, "Services  -  Gateway (Ports) interfaces", fontsize=10, **txt)

# 1 - DOMAIN (centro)
ax.text(0, 0.55, "1 - DOMAIN", fontsize=15, fontweight="bold", **txt)
ax.text(0, 0.12, "enterprise business rules", fontsize=8.5, style="italic", **txt)
ax.text(0, -0.32, "Entities  -  Value Objects", fontsize=9.5, **txt)
ax.text(0, -0.66, "Enums  -  Exceptions", fontsize=9.5, **txt)

# Seta "dependencia sempre para dentro" (da borda ao centro, lado esquerdo)
arrow = FancyArrowPatch((-6.9, 0), (-1.9, 0), arrowstyle="-|>", mutation_scale=32,
                        color="#E53935", linewidth=3.5, zorder=6)
ax.add_patch(arrow)
ax.text(-4.4, 0.42, "Regra de dependencia", fontsize=12.5, fontweight="bold",
        ha="center", va="center", color="#B71C1C", zorder=7)
ax.text(-4.4, -0.42, "SEMPRE para DENTRO (DIP)", fontsize=11, fontweight="bold",
        ha="center", va="center", color="#B71C1C", zorder=7)

# Seta lado direito tambem (simetria)
arrow2 = FancyArrowPatch((6.9, 0), (1.9, 0), arrowstyle="-|>", mutation_scale=32,
                         color="#E53935", linewidth=3.5, zorder=6)
ax.add_patch(arrow2)

# Titulo e rodape
ax.text(0, 7.25, "Oficina Mecanica - Clean Architecture (4 Aneis)",
        fontsize=20, fontweight="bold", ha="center", color="#1B3A57")
ax.text(0, -7.15,
        "O nucleo (Domain/UseCase) nao conhece frameworks. Adapters implementam as Ports (inversao de dependencia).\n"
        "Regras verificadas automaticamente no build por ArchUnit.",
        fontsize=10.5, ha="center", va="center", color="#37474F")

plt.tight_layout()
plt.savefig("oficina-clean-arch-aneis.png", dpi=140, bbox_inches="tight", facecolor="white")
print("ok")
