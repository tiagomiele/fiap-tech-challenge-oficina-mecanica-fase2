from diagrams import Diagram, Cluster, Edge
from diagrams.onprem.client import Users
from diagrams.onprem.vcs import Github
from diagrams.onprem.ci import GithubActions
from diagrams.onprem.container import Docker
from diagrams.onprem.iac import Terraform
from diagrams.onprem.security import Trivy
from diagrams.programming.language import Java
from diagrams.programming.framework import Spring
from diagrams.aws.compute import ECR
from diagrams.aws.database import RDS, Dynamodb
from diagrams.aws.storage import S3
from diagrams.aws.network import ELB, InternetGateway, NATGateway
from diagrams.aws.engagement import SimpleEmailServiceSes
from diagrams.k8s.compute import Pod, Deploy
from diagrams.k8s.network import SVC
from diagrams.k8s.clusterconfig import HPA
from diagrams.k8s.podconfig import CM, Secret

graph_attr = {
    "fontsize": "20",
    "labelloc": "t",
    "bgcolor": "white",
    "pad": "0.7",
    "nodesep": "0.5",
    "ranksep": "1.0",
    "splines": "spline",
    "compound": "true",
}

with Diagram(
    "Oficina Mecanica - Arquitetura Fim a Fim (Codigo -> CI/CD -> IaC -> AWS)",
    filename="oficina-arquitetura-ludica",
    show=False,
    direction="LR",
    outformat="png",
    graph_attr=graph_attr,
):

    usuarios = Users("Cliente / Perfil 02 (Admin)\n/ Perfil 03 (Tecnico)")
    mail = SimpleEmailServiceSes("Mailtrap (SMTP)\nnotificacao de status")

    with Cluster("Desenvolvimento & CI/CD  (GitHub / GitHub Actions)"):
        gh = Github("Repositorio\noficina-backend")

        with Cluster("CI  (ci.yml)"):
            build = Java("Build + Testes\nMaven / JUnit\nJaCoCo + ArchUnit")
            sec = Trivy("Trivy scan\n+ SBOM CycloneDX\n-> Dependency-Track")

        with Cluster("CD  (cd.yml)  -  promocao por ambiente"):
            dbuild = Docker("Docker build")
            ghcr = ECR("GHCR\n(Container Registry)")
            promo = GithubActions("STG -> Pre-prod\n-> (aprovacao) -> Prod")

        with Cluster("IaC  (infra.yml)"):
            tf = Terraform("Terraform\n@ Terraform Cloud")

        gh >> Edge(label="push / PR") >> build >> sec
        gh >> dbuild >> Edge(label="push imagem") >> ghcr >> promo
        gh >> tf

    with Cluster("AWS Cloud  (provisionada via Terraform)"):

        with Cluster("Terraform State"):
            s3 = S3("S3\ntfstate")
            ddb = Dynamodb("DynamoDB\nlock")

        with Cluster("VPC 10.0.0.0/16"):

            with Cluster("Public Subnets (2 AZs)"):
                igw = InternetGateway("Internet Gateway")
                nat = NATGateway("NAT Gateway")
                elb = ELB("Load Balancer (ELB)")

            with Cluster("Private Subnets (2 AZs)"):

                with Cluster("EKS Cluster v1.31  -  Node Group t3.medium (2-5)"):
                    svc = SVC("Service\n(LoadBalancer)")
                    hpa = HPA("HPA 2-5 pods")
                    cfg = CM("ConfigMap")
                    sct = Secret("Secret\n(DB / JWT / SMTP)")
                    with Cluster("Deployment: oficina-app (Java 21 / Spring Boot 3)"):
                        app = Spring("Spring Web + Security(JWT)\nData JPA + Flyway\nMail + SpringDoc")
                        pod1 = Pod("pod #1")
                        pod2 = Pod("pod #2")

                rds = RDS("RDS PostgreSQL 16\n(db.t3.micro)")

    # ---- Fluxo de runtime (usuarios -> app) ----
    usuarios >> Edge(label="HTTPS (JWT admin/tecnico)") >> igw
    igw >> Edge(label="ingress :80") >> elb >> svc
    svc >> hpa >> [pod1, pod2]
    pod1 >> Edge(style="dotted") >> app
    pod2 >> Edge(style="dotted") >> app
    cfg >> Edge(style="dotted", label="env") >> app
    sct >> Edge(style="dotted") >> app
    app >> Edge(label="JDBC / JPA + Flyway") >> rds
    app >> Edge(label="SMTP (Spring Mail)") >> mail

    # ---- CD -> deploy no cluster ----
    promo >> Edge(label="deploy (kubectl apply)", style="dashed", color="darkgreen") >> svc

    # ---- Terraform provisiona a infra ----
    tf >> Edge(label="provisiona", style="dashed", color="purple") >> igw
    tf >> Edge(style="dashed", color="purple") >> nat
    tf >> Edge(label="provisiona EKS/RDS", style="dashed", color="purple") >> hpa
    tf >> Edge(style="dashed", color="purple") >> rds
    tf >> Edge(label="state", style="dashed", color="purple") >> s3
    s3 - Edge(style="dashed", color="purple") - ddb
