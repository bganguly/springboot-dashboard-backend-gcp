import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";
import * as random from "@pulumi/random";

const config    = new pulumi.Config();
const gcpConfig = new pulumi.Config("gcp");

const project        = gcpConfig.require("project");
const region         = gcpConfig.get("region")         ?? "us-central1";
const namePrefix     = config.get("namePrefix")         ?? "dash";
const dbName         = config.get("dbName")             ?? "app";
const dbUsername     = config.get("dbUsername")         ?? "appuser";
const dbVmType       = config.get("dbVmType")           ?? "n2-standard-4";
const dbDiskGb       = config.getNumber("dbDiskGb")     ?? 35;
const backendImage   = config.get("backendImage")       ?? "";
const backendVmType  = config.get("backendVmType")      ?? "e2-standard-2";

// ── APIs ──────────────────────────────────────────────────────────────────────
const apis = [
  "compute.googleapis.com",
  "artifactregistry.googleapis.com",
  "secretmanager.googleapis.com",
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

// Allow anything in VPC to reach Postgres on 5432
new gcp.compute.Firewall("allow-internal-to-db", {
  name: `${namePrefix}-allow-internal-db`,
  network: network.id,
  direction: "INGRESS",
  sourceRanges: ["10.0.0.0/8"],
  allows: [{ protocol: "tcp", ports: ["5432"] }],
});

// Allow public HTTP to backend VM on 8080
new gcp.compute.Firewall("allow-http-backend", {
  name: `${namePrefix}-allow-http-backend`,
  network: network.id,
  direction: "INGRESS",
  targetTags: [`${namePrefix}-backend`],
  sourceRanges: ["0.0.0.0/0"],
  allows: [{ protocol: "tcp", ports: ["8080"] }],
});

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
DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-16 postgresql-server-dev-16 build-essential git
PG_CONFIG=/usr/lib/postgresql/16/bin/pg_config
git clone --depth 1 https://github.com/pgbigm/pg_bigm.git /tmp/pg_bigm
make -C /tmp/pg_bigm USE_PGXS=1 PG_CONFIG="$PG_CONFIG"
make -C /tmp/pg_bigm USE_PGXS=1 PG_CONFIG="$PG_CONFIG" install
rm -rf /tmp/pg_bigm
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
});

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

new gcp.projects.IAMMember("backend-ar-reader", {
  project,
  role: "roles/artifactregistry.reader",
  member: pulumi.interpolate`serviceAccount:${backendSa.email}`,
});

// ── Backend on GCE ────────────────────────────────────────────────────────────
// Startup script: installs Docker + gcloud, pulls the image from Artifact Registry,
// fetches DATABASE_URL from Secret Manager, and runs the container.
// Runs on every boot so a VM reset picks up a new image tag.
const _backendStartupScript = `#!/bin/bash
set -euo pipefail
_meta() { curl -sf "http://metadata.google.internal/computeMetadata/v1/instance/attributes/$1" -H Metadata-Flavor:Google; }
BACKEND_IMAGE=$(_meta backend-image)
DB_SECRET=$(_meta db-secret-name)
PROJECT=$(curl -sf "http://metadata.google.internal/computeMetadata/v1/project/project-id" -H Metadata-Flavor:Google)
REGION="${region}"

if ! command -v docker >/dev/null 2>&1; then
  apt-get update -qq
  apt-get install -y docker.io
  systemctl enable docker && systemctl start docker
fi

if ! command -v gcloud >/dev/null 2>&1; then
  echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" > /etc/apt/sources.list.d/google-cloud-sdk.list
  curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
  apt-get update -qq && apt-get install -y google-cloud-cli
fi

gcloud auth configure-docker "$REGION-docker.pkg.dev" --quiet
DATABASE_URL=$(gcloud secrets versions access latest --secret="$DB_SECRET" --project="$PROJECT")
docker rm -f backend 2>/dev/null || true
docker pull "$BACKEND_IMAGE"
docker run -d --name backend --restart=unless-stopped -p 8080:8080 -e DATABASE_URL="$DATABASE_URL" "$BACKEND_IMAGE"`;

const backendVm = new gcp.compute.Instance("backend-vm", {
  name: `${namePrefix}-backend`,
  machineType: backendVmType,
  zone: `${region}-a`,
  bootDisk: {
    initializeParams: {
      image: "debian-cloud/debian-12",
      size: 20,
      type: "pd-ssd",
    },
  },
  networkInterfaces: [{
    network: network.id,
    subnetwork: subnet.id,
    accessConfigs: [{}],
  }],
  serviceAccount: {
    email: backendSa.email,
    scopes: ["cloud-platform"],
  },
  metadata: {
    "backend-image": backendImage !== "" ? backendImage : "gcr.io/cloudrun/hello",
    "db-secret-name": `${namePrefix}-database-url`,
    "startup-script": _backendStartupScript,
  },
  tags: [`${namePrefix}-backend`],
}, { dependsOn: [dbUrlSecretVersion, registry] });

const backendVmExternalIp = backendVm.networkInterfaces.apply(
  nics => nics[0].accessConfigs![0].natIp!
);

// ── Outputs ───────────────────────────────────────────────────────────────────
export const dbVmInternalIp   = dbVmIp;
export const artifactRegistry = pulumi.interpolate`${region}-docker.pkg.dev/${project}/${registry.repositoryId}`;
export const backendUrl       = pulumi.interpolate`http://${backendVmExternalIp}:8080`;
export const backendVmName    = pulumi.output(`${namePrefix}-backend`);
export const databaseUrl      = pulumi.secret(
  pulumi.interpolate`postgresql://${dbUsername}:${dbPassword.result}@${dbVmIp}:5432/${dbName}`
);
