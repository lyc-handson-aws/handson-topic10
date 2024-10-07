import pulumi
import pulumi_kubernetes as k8s

# Minikube does not implement services of type `LoadBalancer`; require the user to specify if we're
# running on minikube, and if so, create only services of type ClusterIP.
config = pulumi.Config()

app_name = "nginx"
app_container = "nginx:latest"
app_labels = { "app": app_name }


# Create a Namespace
namespace = k8s.core.v1.Namespace(
    app_name+'-ns',
    metadata={
        "name": app_name+'-ns'
    })

deployment = k8s.apps.v1.Deployment(
    app_name+'-deployment',
    metadata={
        "namespace": namespace.metadata["name"],
        "name": app_name+'-deployment'
    },
    spec={
        "selector": {
            "match_labels": {
                app_labels
            }
        },
        "replicas": 2,
        "template": {
            "metadata": {
                "labels": {
                    app_labels
                }
            },
            "spec": {
                "containers": [{
                    "name": app_name,
                    "image": app_container,
                    "ports": [{
                        "container_port": 80
                    }]
                }]
            }
        }
    })

service = k8s.core.v1.Service(
    app_name+'-service',
    metadata={
        "namespace": namespace.metadata["name"],
        "name": app_name+'-service',
        "labels": deployment.spec["template"]["metadata"]["labels"],
    },
    spec={
        "selector": {
            app_labels
        },
        "ports": [{
            "port": 80,
            "target_port": 80,
            "protocol": "TCP" 
        }],
        "type": "ClusterIP"
    })

# Create an Ingress
ingress = k8s.networking.v1.Ingress("nginx-ingress",
    metadata={
        "namespace": namespace.metadata["name"],
        "name": "nginx-ingress",
        "annotations": {
            "nginx.ingress.kubernetes.io/rewrite-target": "/"
        }
    },
    spec={
        "rules": [{
            "http": {
                "paths": [{
                    "path": "/",
                    "path_type": "Prefix",
                    "backend": {
                        "service": {
                            "name": service.metadata["name"],
                            "port": {
                                "number": 80
                            }
                        }
                    }
                }]
            }
        }]
    })


# Export outputs

# When "done", this will print the public IP.
result = None
result = service.spec.apply(lambda v: v["cluster_ip"] if "cluster_ip" in v else None)
pulumi.export("ip", result)



pulumi.export('namespace', namespace.metadata["name"])
pulumi.export('deployment', deployment.metadata["name"])
pulumi.export('service', service.metadata["name"])
pulumi.export('ingress', ingress.metadata["name"])