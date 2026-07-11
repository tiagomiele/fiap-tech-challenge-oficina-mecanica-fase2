from diagrams import Diagram, Cluster, Edge
from diagrams.onprem.client import Users
from diagrams.onprem.ci import GithubActions
from diagrams.onprem.iac import Terraform
from diagrams.programming.framework import Spring
from diagrams.aws.compute import ECR
from diagrams.aws.database import RDS
from diagrams.aws.network import ELB, InternetGateway, NATGateway
from diagrams.k8s.compute import Pod
from diagrams.k8s.clusterconfig import HPA

graph_attr = {
    "fontsize": "22",
    "labelloc": "t",
    "bgcolor": "white",
    "pad": "0.7",
    "nodesep": "0.6",
    "ranksep": "1.1",
    "splines": "spline",
    "compound": "true",
}
node_attr = {"fontsize": "13"}

with Diagram(
    "Oficina Mecanica - Arquitetura de Infraestrutura (AWS)",
    filename="oficina-infra-aws",
    show=False,
    direction="LR",
    outformat="png",
    graph_attr=graph_attr,
    node_attr=node_attr,
):

    internet = Users("Trafego externo\n(porta 80 / HTTP)")
    tf = Terraform("Terraform (/infra)\nprovisiona a infra")
    cicd = GithubActions("CI/CD\n(GitHub Actions)")

    with Cluster("AWS Cloud"):

        registry = ECR("GHCR *\nregistry da imagem Docker")

        with Cluster("VPC 10.0.0.0/16"):

            with Cluster("Subnets Publicas (2 AZs)"):
                igw = InternetGateway("Internet Gateway")
                elb = ELB("Load Balancer (ELB)")
                nat = NATGateway("NAT Gateway")

            with Cluster("Subnets Privadas (2 AZs)"):
                with Cluster("EKS Cluster 1.31  -  Node Group t3.medium (2-5)"):
                    hpa = HPA("HPA 2-5 pods")
                    with Cluster("oficina-app x2+ (Spring Boot 3)"):
                        pod1 = Pod("pod #1")
                        pod2 = Pod("pod #2")
                rds = RDS("RDS PostgreSQL 16\n(db.t3.micro)")

    # Trafego externo -> ELB -> pods
    internet >> Edge(label="porta 80") >> igw >> Edge(label="ingress") >> elb
    elb >> hpa >> [pod1, pod2]

    # App -> banco
    pod1 >> Edge(label="JDBC/JPA") >> rds
    pod2 >> Edge() >> rds

    # Egress dos pods pela NAT
    pod2 >> Edge(label="egress", style="dotted") >> nat

    # CI/CD -> registry -> deploy nos pods
    cicd >> Edge(label="push imagem") >> registry
    registry >> Edge(label="deploy / pull imagem", style="dashed", color="darkgreen") >> pod1

    # Terraform provisiona
    tf >> Edge(label="provisiona", style="dashed", color="purple") >> igw
    tf >> Edge(style="dashed", color="purple") >> hpa
    tf >> Edge(style="dashed", color="purple") >> rds
