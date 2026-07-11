from diagrams import Diagram, Cluster, Edge
from diagrams.onprem.vcs import Github
from diagrams.onprem.container import Docker
from diagrams.onprem.security import Trivy
from diagrams.programming.language import Java
from diagrams.aws.compute import ECR, EKS
from diagrams.k8s.group import NS
from diagrams.k8s.podconfig import CM, Secret
from diagrams.k8s.compute import Deploy
from diagrams.k8s.network import SVC
from diagrams.k8s.clusterconfig import HPA

graph_attr = {
    "fontsize": "22",
    "labelloc": "t",
    "bgcolor": "white",
    "pad": "0.7",
    "nodesep": "0.55",
    "ranksep": "1.0",
    "splines": "spline",
}
node_attr = {"fontsize": "13"}

with Diagram(
    "Oficina Mecanica - Fluxo de Deploy (CI/CD)",
    filename="oficina-fluxo-cicd",
    show=False,
    direction="TB",
    outformat="png",
    graph_attr=graph_attr,
    node_attr=node_attr,
):

    dev = Github("Desenvolvedor\npush / merge na main")

    with Cluster("CI  (.github/workflows/ci.yml)"):
        ci_build = Java("1. Build (mvnw verify)\n2. Testes + JaCoCo")
        ci_sec = Trivy("3. SBOM (CycloneDX)\n4. Trivy (vulnerabilidades)")
        ci_build >> ci_sec

    with Cluster("CD  (.github/workflows/cd.yml + deploy.yml)"):
        dbuild = Docker("G1. Docker build")
        ghcr = ECR("push imagem -> GHCR")

        with Cluster("G2/G3. kubectl apply -f k8s/  (por ambiente)"):
            ns = NS("namespace")
            conf = CM("configmap")
            sec = Secret("secret")
            pg = Deploy("postgres (banco)")
            app = Deploy("app + service")
            hpa = HPA("hpa (auto-scaling)")
            ns >> conf >> sec >> pg >> app >> hpa

        dbuild >> ghcr >> Edge(label="deploy") >> ns

    result = EKS("Cluster Kubernetes atualizado\n(app + banco no ar)")

    dev >> Edge(label="dispara") >> ci_build
    ci_sec >> Edge(label="sucesso", color="darkgreen") >> dbuild
    hpa >> Edge(label="rollout status", color="darkgreen") >> result
