import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";
import * as random from "@pulumi/random";

const config    = new pulumi.Config();
const gcpConfig = new pulumi.Config("gcp");

const project       = gcpConfig.require("project");
const region        = gcpConfig.get("region")       ?? "us-central1";
const namePrefix    = config.get("namePrefix")       ?? "dash";
const dbName        = config.get("dbName")           ?? "app";
const dbUsername    = config.get("dbUsername")       ?? "appuser";
const dbVmType         = config.get("dbVmType")            ?? "n2-standard-4";
const dbDiskGb         = config.getNumber("dbDiskGb")      ?? 35;
const backendImage     = config.get("backendImage")        ?? "";
const minInstanceCount = config.getNumber("minInstanceCount") ?? 1;
const maxInstanceCount = config.getNumber("maxInstanceCount") ?? 5;
const cpu              = config.get("cpu")                 ?? "2";
const memory           = config.get("memory")              ?? "1Gi";

// ── APIs ──────────────────────────────────────────────────────────────────────
const apis = [
  "compute.googleapis.com",
  "sqladmin.googleapis.com",
  "run.googleapis.com",
  "artifactregistry.googleapis.com",
  "secretmanager.googleapis.com",
  "vpcaccess.googleapis.com",
  "servicenetworking.googleapis.com",
].map(api => new gcp.projects.Service(`api-${api.split(".")[0]}`, {
  project,
  service: api,
  disableOnDestroy: false,
}));

// ── VPC ───────────────────────────────────────────────────────────────────────
const network = new gcp.compute.Network("vpc", {
  name: `${namePrefix}-vpc`,
  autoCreateSubnetworks: false,
}, { dependsOn: apis });

const subnet = new gcp.compute.Subnetwork("subnet", {
  name: `${namePrefix}-subnet`,
  ipCidrRange: "10.8.0.0/20",
  region,
  network: network.id,
});

const connectorSubnet = new gcp.compute.Subnetwork("connector-subnet", {
  name: `${namePrefix}-connector-subnet`,
  ipCidrRange: "10.8.16.0/28",
  region,
  network: network.id,
});

const privateIpRange = new gcp.compute.GlobalAddress("sql-ip-range", {
  name: `${namePrefix}-sql-ip-range`,
  purpose: "VPC_PEERING",
  addressType: "INTERNAL",
  prefixLength: 20,
  network: network.id,
});

const privateVpc = new gcp.servicenetworking.Connection("private-vpc", {
  network: network.id,
  service: "servicenetworking.googleapis.com",
  reservedPeeringRanges: [privateIpRange.name],
}, { dependsOn: apis });

new gcp.compute.Firewall("allow-connector-to-sql", {
  name: `${namePrefix}-allow-connector-sql`,
  network: network.id,
  direction: "INGRESS",
  sourceRanges: ["10.8.16.0/28"],
  allows: [{ protocol: "tcp", ports: ["5432"] }],
});

// Allow anything in VPC 10.x.x.x to reach Postgres VM on 5432
new gcp.compute.Firewall("allow-gke-to-sql", {
  name: `${namePrefix}-allow-gke-sql`,
  network: network.id,
  direction: "INGRESS",
  sourceRanges: ["10.0.0.0/8"],
  allows: [{ protocol: "tcp", ports: ["5432"] }],
});

const connector = new gcp.vpcaccess.Connector("connector", {
  name: `${namePrefix}-connector`,
  region,
  subnet: { name: connectorSubnet.name },
  minInstances: 2,
  maxInstances: 3,
}, { dependsOn: apis });

// ── Postgres on GCE ───────────────────────────────────────────────────────────
const dbPassword = new random.RandomPassword("db-password", {
  length: 24,
  special: false,
});

// Runs once at first boot (guarded by sentinel). Installs Postgres 16 + pg_bigm,
// configures VPC-wide access, and creates the app user/db.
const _startupScript = `#!/bin/bash
set -euo pipefail
SENTINEL=/var/lib/postgresql/.pg16_initialized
[ -f "$SENTINEL" ] && exit 0
_meta() { curl -sf "http://metadata.google.internal/computeMetadata/v1/instance/attributes/$1" -H Metadata-Flavor:Google; }
DB_PASS=$(_meta db-password)
DB_NAME=$(_meta db-name)
DB_USER=$(_meta db-username)
echo "deb http://apt.postgresql.org/pub/repos/apt bookworm-pgdg main" > /etc/apt/sources.list.d/pgdg.list
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg
DEBIAN_FRONTEND=noninteractive apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-16 postgresql-server-dev-16 build-essential python3-pip
python3 -m pip install pgxnclient --break-system-packages
pgxn install pg_bigm
sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" /etc/postgresql/16/main/postgresql.conf
echo "shared_preload_libraries = 'pg_bigm'" >> /etc/postgresql/16/main/postgresql.conf
echo "host all all 10.0.0.0/8 scram-sha-256" >> /etc/postgresql/16/main/pg_hba.conf
systemctl restart postgresql@16-main
sleep 5
sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';"
sudo -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;"
sudo -u postgres psql -d $DB_NAME -c "CREATE EXTENSION IF NOT EXISTS pg_bigm;"
touch "$SENTINEL"`;

const dbVm = new gcp.compute.Instance("pg-vm", {
  name: `${namePrefix}-pg`,
  machineType: dbVmType,
  zone: `${region}-a`,
  bootDisk: {
    initializeParams: {
      image: "debian-cloud/debian-12",
      size: dbDiskGb,
      type: "pd-ssd",
    },
  },
  networkInterfaces: [{
    network: network.id,
    subnetwork: subnet.id,
  }],
  metadata: {
    "db-password": dbPassword.result,
    "db-name": dbName,
    "db-username": dbUsername,
    "startup-script": _startupScript,
  },
  tags: [`${namePrefix}-pg`],
}, { dependsOn: [privateVpc] });

const dbVmIp = dbVm.networkInterfaces.apply(nics => nics[0].networkIp);

// ── Secret Manager ────────────────────────────────────────────────────────────
const dbUrlSecret = new gcp.secretmanager.Secret("database-url", {
  secretId: `${namePrefix}-database-url`,
  replication: { auto: {} },
}, { dependsOn: apis });

const dbUrlSecretVersion = new gcp.secretmanager.SecretVersion("database-url-v1", {
  secret: dbUrlSecret.id,
  secretData: pulumi.interpolate`postgresql://${dbUsername}:${dbPassword.result}@${dbVmIp}:5432/${dbName}`,
}, { retainOnDelete: true });

// ── Artifact Registry ─────────────────────────────────────────────────────────
const registry = new gcp.artifactregistry.Repository("repo", {
  location: region,
  repositoryId: `${namePrefix}-repo`,
  format: "DOCKER",
}, { dependsOn: apis });

// ── Service Account ───────────────────────────────────────────────────────────
const backendSa = new gcp.serviceaccount.Account("backend-sa", {
  accountId: `${namePrefix}-backend-sa`,
  displayName: "Dashboard Backend SA",
});

new gcp.secretmanager.SecretIamMember("backend-db-url-access", {
  secretId: dbUrlSecret.id,
  role: "roles/secretmanager.secretAccessor",
  member: pulumi.interpolate`serviceAccount:${backendSa.email}`,
});

// ── Cloud Run: Backend ────────────────────────────────────────────────────────
const backendService = new gcp.cloudrunv2.Service("backend", {
  name: `${namePrefix}-backend`,
  location: region,
  template: {
    serviceAccount: backendSa.email,
    vpcAccess: {
      networkInterfaces: [{
        network: network.id,
        subnetwork: subnet.id,
      }],
      egress: "PRIVATE_RANGES_ONLY",
    },
    containers: [{
      image: backendImage !== "" ? backendImage : "us-docker.pkg.dev/cloudrun/container/hello",
      ports: [{ containerPort: 8080 }],
      resources: { limits: { cpu, memory } },
      startupProbe: {
        tcpSocket: { port: 8080 },
        initialDelaySeconds: 10,
        periodSeconds: 15,
        failureThreshold: 60,  // 60 * 15s = 15 min — covers long Flyway migrations
        timeoutSeconds: 5,
      },
      envs: [{
        name: "DATABASE_URL",
        valueSource: {
          secretKeyRef: {
            secret: dbUrlSecret.secretId,
            version: dbUrlSecretVersion.version,
          },
        },
      }],
    }],
    scaling: { minInstanceCount, maxInstanceCount },
  },
  traffics: [{ type: "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST", percent: 100 }],
}, { dependsOn: [registry] });

new gcp.cloudrunv2.ServiceIamMember("backend-public", {
  project,
  location: region,
  name: backendService.name,
  role: "roles/run.invoker",
  member: "allUsers",
});

// ── Outputs ───────────────────────────────────────────────────────────────────
export const dbVmInternalIp    = dbVmIp;
export const artifactRegistry  = pulumi.interpolate`${region}-docker.pkg.dev/${project}/${registry.repositoryId}`;
export const backendUrl        = backendService.uri;
export const databaseUrl       = pulumi.secret(
  pulumi.interpolate`postgresql://${dbUsername}:${dbPassword.result}@${dbVmIp}:5432/${dbName}`
);
