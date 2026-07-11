from diagrams import Diagram, Cluster, Edge
from diagrams.onprem.client import Users
from diagrams.onprem.vcs import Github
from diagrams.onprem.ci import GithubActions
from diagrams.onprem.iac import Terraform
from diagrams.programming.framework import Spring
from diagrams.aws.compute import EKS
from diagrams.aws.database import RDS
from diagrams.aws.network import ELB
from diagrams.aws.engagement import SimpleEmailServiceSes

graph_attr = {
    "fontsize": "22",
    "labelloc": "t",
    "bgcolor": "white",
    "pad": "0.8",
    "nodesep": "0.8",
    "ranksep": "1.6",
    "splines": "spline",
}
node_attr = {"fontsize": "14"}

with Diagram(
    "Oficina Mecanica - Arquitetura (Visao de Alto Nivel)",
    filename="oficina-arquitetura-altonivel",
    show=False,
    direction="LR",
    outformat="png",
    graph_attr=graph_attr,
    node_attr=node_attr,
):

    usuarios = Users("Usuarios\nCliente / Admin / Tecnico")
    mail = SimpleEmailServiceSes("Mailtrap\n(e-mail / SMTP)")

    with Cluster("Engenharia  (GitHub)"):
        repo = Github("Codigo-fonte\noficina-backend")
        cicd = GithubActions("CI/CD\nbuild + testes + seguranca\n-> imagem (GHCR)")
        iac = Terraform("IaC\nTerraform Cloud")
        repo >> cicd
        repo >> iac

    with Cluster("AWS Cloud"):
        elb = ELB("Load Balancer")
        with Cluster("Kubernetes / EKS"):
            app = Spring("Aplicacao\nSpring Boot 3 (Java 21)\n2-5 pods (autoescala)")
        db = RDS("Banco de dados\nPostgreSQL")
        elb >> app
        app >> Edge(label="JPA") >> db

    # Fluxo principal
    usuarios >> Edge(label="HTTPS (JWT)") >> elb
    app >> Edge(label="SMTP") >> mail

    # Pipeline e infra
    cicd >> Edge(label="deploy", style="dashed", color="darkgreen") >> app
    iac >> Edge(label="provisiona a nuvem", style="dashed", color="purple") >> elb
