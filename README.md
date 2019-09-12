# cloud-sql-proxy-gce
GCE start-up script to install Cloud SQL Proxy as a system service and connect to a Cloud SQL MySQL instance

## Usage
Load the cloud-sql-proxy.sh	into a GCS bucket


```
gcloud beta compute --project=<PROJECT_NAME> instances create <INSTANCE_NAME> \
    --zone=us-central1-a --machine-type=n2-standard-2 \
    --image=debian-9-drawfork-v20190702 \
    --metadata startup-script-url=<GCS_LOCATION>/cloud-sql-proxy.sh,cloud-sql-instance-name=<CLOUD_SQL_PROJ:<CLOUD_SQL_REGION>:<CLOUD_SQL_INSTANCE_NAME>,cloud-sql-proxy-port=3306,cloud-sql-proxy-private=false
```
Note: ensure service account used to create the GCE instance has the [required permissions](https://cloud.google.com/sql/docs/mysql/sql-proxy#permissions) to access the Cloud SQL instance.

## Testing
1. Login to the GCP instance.
2. Test access to Cloud SQL using MySQL
```
mysql -u root -p --host 127.0.0.1
```

## License
APACHE LICENSE, VERSION 2.0

## Disclaimer
This is not an official Google product.
