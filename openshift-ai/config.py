"""
OpenShift AI Configuration for Data Flywheel
Configure all service endpoints for in-cluster access
"""

import os

# Namespace where all services are deployed
NAMESPACE = "hacohen-flywheel"

# Data Flywheel Core Services
API_BASE_URL = f"http://df-api-service.{NAMESPACE}.svc.cluster.local:8000"
ELASTICSEARCH_URL = f"http://elasticsearch-master.{NAMESPACE}.svc.cluster.local:9200"
MONGODB_URL = f"mongodb://flywheel-infra-mongodb.{NAMESPACE}.svc.cluster.local:27017"
REDIS_URL = f"redis://flywheel-infra-redis-master.{NAMESPACE}.svc.cluster.local:6379/0"
MLFLOW_TRACKING_URI = f"http://df-mlflow-service.{NAMESPACE}.svc.cluster.local:5000"

# NeMo Microservices Platform endpoints
NEMO_BASE_URL = f"http://nemo-gateway.{NAMESPACE}.svc.cluster.local"
NIM_BASE_URL = f"http://nemo-gateway.{NAMESPACE}.svc.cluster.local"
DATASTORE_BASE_URL = f"http://nemodatastore-sample.{NAMESPACE}.svc.cluster.local:8000"

# External route (for outside-cluster access if needed)
NIM_EXTERNAL_URL = (
    "http://nemo-gateway-hacohen-flywheel.apps.ai-dev05.kni.syseng.devcluster.openshift.com"
)


def configure_environment():
    """Set all environment variables for OpenShift AI"""
    os.environ["API_BASE_URL"] = API_BASE_URL
    os.environ["ELASTICSEARCH_URL"] = ELASTICSEARCH_URL
    os.environ["MONGODB_URL"] = MONGODB_URL
    os.environ["REDIS_URL"] = REDIS_URL
    os.environ["MLFLOW_TRACKING_URI"] = MLFLOW_TRACKING_URI
    os.environ["NEMO_BASE_URL"] = NEMO_BASE_URL
    os.environ["NIM_BASE_URL"] = NIM_BASE_URL
    os.environ["DATASTORE_BASE_URL"] = DATASTORE_BASE_URL

    print("✓ OpenShift AI environment configured")
    print(f"  Namespace: {NAMESPACE}")
    print(f"  API URL: {API_BASE_URL}")
    print(f"  Elasticsearch: {ELASTICSEARCH_URL}")
    print(f"  MLflow: {MLFLOW_TRACKING_URI}")
    print(f"  NeMo Gateway: {NEMO_BASE_URL}")


# Auto-configure on import
configure_environment()
