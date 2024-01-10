#!/bin/bash

tap_secrets_file="$HOME/.tap/tap-secrets"

# Check if the file exists
if [[ -f "$tap_secrets_file" ]]; then
    while IFS='=' read -r key value || [ -n "$key" ]; do
        if [[ -n "$key" ]]; then
            # Set each key-value pair as an environment variable
            export "$key"="$value"
        fi
    done < "$tap_secrets_file"
else
    echo "~/.tap/tap-secrets file does not exist."
fi

echo ""
echo "Removing old directories if any"
echo "-------------------------------"

rm -Rf -- */
rm -f tap.pdf
rm -f *.html

echo ""
echo "Downloading PIVNET"
echo "------------------"

docker login registry.tanzu.vmware.com -u $IMGPKG_REGISTRY_USERNAME -p $IMGPKG_REGISTRY_PASSWORD

mkdir -p pivnet

# Check if the OS is Mac or Linux
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "Running on macOS"
    # Check CPU architecture on macOS
    cpu_arch=$(uname -m)
    if [[ "$cpu_arch" == "arm64" ]]; then
        echo "Apple Silicon (M1)"
        wget -P pivnet "https://github.com/pivotal-cf/pivnet-cli/releases/download/v$PIVNET_VERSION/pivnet-darwin-arm64-4.1.1"
        export PIVNET="$PWD/pivnet/pivnet-darwin-arm64-4.1.1"
    else
        echo "Intel"
        # Commands specific to Intel CPUs
        wget -P pivnet "https://github.com/pivotal-cf/pivnet-cli/releases/download/v$PIVNET_VERSION/pivnet-darwin-amd64-4.1.1"
        export PIVNET=$PWD/pivnet/pivnet-darwin-amd64-4.1.1
    fi
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    echo "Running on Linux"
    # Linux specific commands
    wget -P pivnet "https://github.com/pivotal-cf/pivnet-cli/releases/download/v$PIVNET_VERSION/pivnet-linux-amd64-4.1.1"

    export PIVNET=$PWD/pivnet/pivnet-linux-amd64-4.1.1
else
    echo "Unsupported OS"
    exit 1
fi

chmod +x pivnet/*

echo ""
echo "Downloading jq"
echo "-----------------------------"

mkdir -p jq
wget -P jq https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-amd64
wget -P jq https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-windows-amd64.exe
wget -P jq https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-macos-amd64
wget -P jq https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-macos-arm64
chmod +x jq/*

echo ""
echo "Logging in to Tanzu Network"
echo "---------------------------"

$PIVNET login --api-token $PIVNET_TOKEN
$PIVNET accept-eula -p 'tanzu-application-platform' -r $TAP_VERSION

echo ""
echo "Downloading Tanzu CLIs"
echo "----------------------"

mkdir -p all-tanzu-clis

$PIVNET product-files -p 'tanzu-application-platform' -r $TAP_VERSION > slugs.txt

# Check if the OS is Mac or Linux
if [[ "$OSTYPE" == "darwin"* ]]; then
    # Check CPU architecture on macOS
    cpu_arch=$(uname -m)
    if [[ "$cpu_arch" == "arm64" ]]; then
        export TANZU_CLI_SLUG=$(grep 'tanzu-framework-bundle-mac-arm64' slugs.txt | awk -F'|' '{print $2}' | awk '{$1=$1};1')
        export JQ_CLI="jq/jq-macos-arm64"
    else
        # Commands specific to Intel CPUs
        export TANZU_CLI_SLUG=$(grep 'tanzu-core-cli-mac' slugs.txt | awk -F'|' '{print $2}' | awk '{$1=$1};1')
        export JQ_CLI="jq/jq-macos-amd64"
    fi
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # Linux specific commands
    export TANZU_CLI_SLUG=$(grep 'tanzu-core-cli-linux' slugs.txt | awk -F'|' '{print $2}' | awk '{$1=$1};1')
    export JQ_CLI="jq/jq-linux-amd64"
else
    echo "Unsupported OS"
    exit 1
fi

$PIVNET download-product-files -p 'tanzu-application-platform' -r $TAP_VERSION -d all-tanzu-clis --product-file-id $(grep 'tanzu-framework-bundle-mac-arm64' slugs.txt | awk -F'|' '{print $2}' | awk '{$1=$1};1')
$PIVNET download-product-files -p 'tanzu-application-platform' -r $TAP_VERSION -d all-tanzu-clis --product-file-id $(grep 'tanzu-core-cli-mac' slugs.txt | awk -F'|' '{print $2}' | awk '{$1=$1};1')
$PIVNET download-product-files -p 'tanzu-application-platform' -r $TAP_VERSION -d all-tanzu-clis --product-file-id $(grep 'tanzu-core-cli-linux' slugs.txt | awk -F'|' '{print $2}' | awk '{$1=$1};1')
$PIVNET download-product-files -p 'tanzu-application-platform' -r $TAP_VERSION -d all-tanzu-clis --product-file-id $(grep 'tanzu-core-cli-windows' slugs.txt | awk -F'|' '{print $2}' | awk '{$1=$1};1')

echo ""
echo "Downloading Tanzu CLI for this machine"
echo "--------------------------------------"

mkdir -p /tmp/tanzu-cli
$PIVNET download-product-files -p 'tanzu-application-platform' -r $TAP_VERSION -d /tmp/tanzu-cli --product-file-id $TANZU_CLI_SLUG


tar xvf /tmp/tanzu-cli/*.tar.gz -C /tmp/tanzu-cli
rm -f /tmp/tanzu-cli/*.tar.gz
mkdir -p /tmp/tanzu-cli-tmp
find /tmp/tanzu-cli -type f -name "tanzu-cli*" -exec mv {} /tmp/tanzu-cli-tmp/ \;
rm -rf /tmp/tanzu-cli/*
mv /tmp/tanzu-cli-tmp/* /tmp/tanzu-cli/
rm -rf /tmp/tanzu-cli-tmp
mv /tmp/tanzu-cli/* /tmp/tanzu-cli/tanzu
chmod +x /tmp/tancu-cli/*

echo ""
echo "Downloading Tanzu CLI Plugins"
echo "-----------------------------"

export TANZU_CLI="/tmp/tanzu-cli/tanzu"
$TANZU_CLI plugin download-bundle --group vmware-tap/default --to-tar all-tanzu-clis/plugins.tar

echo ""
echo "Downloading all cluster-essentials"
echo "----------------------------------"
mkdir -p all-cluster-essentials

$PIVNET accept-eula -p 'tanzu-cluster-essentials' -r $CLUSTER_ESSENTIALS_VERSION
$PIVNET product-files -p 'tanzu-cluster-essentials' -r $CLUSTER_ESSENTIALS_VERSION > slugs.txt
# Check if the OS is Mac or Linux
if [[ "$OSTYPE" == "darwin"* ]]; then
    # Check CPU architecture on macOS
    cpu_arch=$(uname -m)
    if [[ "$cpu_arch" == "arm64" ]]; then
        export CLUSTER_ESSENTIALS_SLUG=$(grep 'tanzu-cluster-essentials-darwin' slugs.txt | awk -F'|' '{print $2}' | awk '{$1=$1};1')
    else
        # Commands specific to Intel CPUs
        export CLUSTER_ESSENTIALS_SLUG=$(grep 'tanzu-cluster-essentials-darwin' slugs.txt | awk -F'|' '{print $2}' | awk '{$1=$1};1')
    fi
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # Linux specific commands
    export CLUSTER_ESSENTIALS_SLUG=$(grep 'tanzu-cluster-essentials-linux' slugs.txt | awk -F'|' '{print $2}' | awk '{$1=$1};1')
else
    echo "Unsupported OS"
    exit 1
fi

export CLUSTER_ESSENTIALS_YAML_SLUG=$(grep 'tanzu-cluster-essentials-bundle' slugs.txt | awk -F'|' '{print $2}' | awk '{$1=$1};1')
$PIVNET download-product-files -p 'tanzu-cluster-essentials' -r $TAP_VERSION -d all-cluster-essentials --product-file-id $(grep 'tanzu-cluster-essentials-darwin' slugs.txt | awk -F'|' '{print $2}' | awk '{$1=$1};1')
$PIVNET download-product-files -p 'tanzu-cluster-essentials' -r $TAP_VERSION -d all-cluster-essentials --product-file-id $(grep 'tanzu-cluster-essentials-darwin' slugs.txt | awk -F'|' '{print $2}' | awk '{$1=$1};1')
$PIVNET download-product-files -p 'tanzu-cluster-essentials' -r $TAP_VERSION -d all-cluster-essentials --product-file-id $(grep 'tanzu-cluster-essentials-linux' slugs.txt | awk -F'|' '{print $2}' | awk '{$1=$1};1')
$PIVNET download-product-files -p 'tanzu-cluster-essentials' -r $TAP_VERSION -d all-cluster-essentials --product-file-id $(grep 'tanzu-cluster-essentials-windows' slugs.txt | awk -F'|' '{print $2}' | awk '{$1=$1};1')

echo ""
echo "Downloading cluster-essentials for this machine"
echo "-----------------------------------------------"

mkdir -p /tmp/cluster-essentials
$PIVNET download-product-files -p 'tanzu-cluster-essentials' -r $TAP_VERSION -d /tmp/cluster-essentials --product-file-id $CLUSTER_ESSENTIALS_SLUG
$PIVNET download-product-files -p 'tanzu-cluster-essentials' -r $TAP_VERSION -d /tmp/cluster-essentials --product-file-id $CLUSTER_ESSENTIALS_YAML_SLUG


tar xvf /tmp/cluster-essentials/*.tgz -C /tmp/cluster-essentials
chmod +x /tmp/cluster-essentials/*
rm /tmp/cluster-essentials/*.tgz
export CLUSTER_ESSENTIALS_IMAGE_SHA=$(grep "image:" /tmp/cluster-essentials/tanzu-cluster-essentials-bundle-$CLUSTER_ESSENTIALS_VERSION.yml  | awk '{print $2}')

echo ""
echo "Taking note of the sha256 hash"
echo "------------------------------"


export sha256_hash=$(echo "$CLUSTER_ESSENTIALS_IMAGE_SHA" | grep -oE "sha256:[0-9a-fA-F]{64}")

/tmp/cluster-essentials/imgpkg copy -b $CLUSTER_ESSENTIALS_IMAGE_SHA --to-tar all-cluster-essentials/cluster-essentials-bundle.tar --include-non-distributable-layers

echo $CLUSTER_ESSENTIALS_IMAGE_SHA > all-cluster-essentials/sha256_hash.txt

echo ""
echo "Downloading TAP dependencies"
echo "----------------------------"

mkdir -p tap-dependencies
/tmp/cluster-essentials/imgpkg copy \
  -b registry.tanzu.vmware.com/tanzu-application-platform/tap-packages:$TAP_VERSION \
  --to-tar tap-dependencies/tap-packages-$TAP_VERSION.tar \
  --include-non-distributable-layers

cat <<EOT >> tap-dependencies/sample-tap-values.yaml
shared:
  ingress_domain: "INGRESS-DOMAIN"
  image_registry:
    project_path: "SERVER-NAME/REPO-NAME"
    secret:
      name: "KP-DEFAULT-REPO-SECRET"
      namespace: "KP-DEFAULT-REPO-SECRET-NAMESPACE"
  ca_cert_data: |
    -----BEGIN CERTIFICATE-----
    MIIFXzCCA0egAwIBAgIJAJYm37SFocjlMA0GCSqGSIb3DQEBDQUAMEY...
    -----END CERTIFICATE-----
profile: full
ceip_policy_disclosed: true
buildservice:
  kp_default_repository: "KP-DEFAULT-REPO"
  kp_default_repository_secret: # Takes the value from the shared section by default, but can be overridden by setting a different value.
    name: "KP-DEFAULT-REPO-SECRET"
    namespace: "KP-DEFAULT-REPO-SECRET-NAMESPACE"
  exclude_dependencies: true
supply_chain: basic
contour:
  infrastructure_provider: aws
  envoy:
    service:
      type: LoadBalancer
      annotations:
      # This annotation is for air-gapped AWS only.
          service.kubernetes.io/aws-load-balancer-internal: "true"

ootb_supply_chain_basic:
  registry:
      server: "SERVER-NAME" # Takes the value from the shared section by default, but can be overridden by setting a different value.
      repository: "REPO-NAME" # Takes the value from the shared section by default, but can be overridden by setting a different value.
  gitops:
      ssh_secret: "SSH-SECRET"
  maven:
      repository:
         url: https://MAVEN-URL
         secret_name: "MAVEN-CREDENTIALS"

accelerator:
  ingress:
    include: true
    enable_tls: false
  git_credentials:
    secret_name: git-credentials
    username: GITLAB-USER
    password: GITLAB-PASSWORD

appliveview:
  ingressEnabled: true

appliveview_connector:
  backend:
    ingressEnabled: true
    sslDeactivated: false
    host: appliveview.INGRESS-DOMAIN
    caCertData: |-
      -----BEGIN CERTIFICATE-----
      MIIGMzCCBBugAwIBAgIJALHHzQjxM6wMMA0GCSqGSIb3DQEBDQUAMGcxCzAJBgNV
      BAgMAk1OMRQwEgYDVQQHDAtNaW5uZWFwb2xpczEPMA0GA1UECgwGVk13YXJlMRMw
      -----END CERTIFICATE-----

local_source_proxy:
  # Takes the value from the project_path under the image_registry section of shared by default, but can be overridden by setting a different value.
  repository: "EXTERNAL-REGISTRY-FOR-LOCAL-SOURCE"
  push_secret:
    # When set to true, the secret mentioned in this section is automatically exported to Local Source Proxy's namespace.
    name: "EXTERNAL-REGISTRY-FOR-LOCAL-SOURCE-SECRET"
    namespace: "EXTERNAL-REGISTRY-FOR-LOCAL-SOURCE-SECRET-NAMESPACE"
    # When set to true, the secret mentioned in this section is automatically exported to Local Source Proxy's namespace.
    create_export: true

tap_gui:
  app_config:
    auth:
      allowGuestAccess: true  # This allows unauthenticated users to log in to your portal. If you want to deactivate it, make sure you configure an alternative auth provider.
    kubernetes:
      serviceLocatorMethod:
        type: multiTenant
      clusterLocatorMethods:
        - type: config
          clusters:
            - url: https://{KUBERNETES_SERVICE_HOST}:{KUBERNETES_SERVICE_PORT}
              name: host
              authProvider: serviceAccount
              serviceAccountToken: {KUBERNETES_SERVICE_ACCOUNT_TOKEN}
              skipTLSVerify: false
              caData: B64_ENCODED_CA
    catalog:
      locations:
        - type: url
          target: https://GIT-CATALOG-URL/catalog-info.yaml
    #Example Integration for custom GitLab:
    integrations:
      gitlab:
        - host: GITLAB-URL
          token: GITLAB-TOKEN
          apiBaseUrl: https://GITLABURL/api/v4/
    backend:
      reading:
        allow:
          - host: GITLAB-URL # Example URL: gitlab.example.com

metadata_store:
  ns_for_export_app_cert: "MY-DEV-NAMESPACE"
  app_service_type: ClusterIP # Defaults to LoadBalancer. If shared.ingress_domain is set earlier, this must be set to ClusterIP.
EOT


echo ""
echo "Downloading Build Service dependencies"
echo "--------------------------------------"
/tmp/cluster-essentials/imgpkg copy -b registry.tanzu.vmware.com/tanzu-application-platform/full-deps-package-repo:$TAP_VERSION \
  --to-tar=tap-dependencies/full-deps-package-repo.tar

echo ""
echo "Making Grype with DB"
echo "--------------------"


mkdir -p grype-with-db
cd grype-with-db

ESCAPED_1=$(sed 's/[\*\/]/\\&/g' <<<"$GRYPE_FQDN")
rm vulnerability-db*.tar.gz
rm listing.json
wget https://toolbox-data.anchore.io/grype/databases/listing.json
jq --arg v1 "$v1" '{ "available": { "1" : [.available."1"[0]] , "2" : [.available."2"[0]] , "3" : [.available."3"[0]] , "4" : [.available."4"[0]] , "5" : [.available."5"[0]]  } }' listing.json > listing.json.tmp
mv listing.json.tmp listing.json
wget $(cat listing.json | ../$JQ_CLI -r '.available."1"[0].url')
wget $(cat listing.json | ../$JQ_CLI -r '.available."2"[0].url')
wget $(cat listing.json | ../$JQ_CLI -r '.available."3"[0].url')
wget $(cat listing.json | ../$JQ_CLI -r '.available."4"[0].url')
wget $(cat listing.json | ../$JQ_CLI -r '.available."5"[0].url')
sed -i '' -e "s/https:\/\/toolbox-data.anchore.io\/grype\/databases/$ESCAPED_1/g" listing.json

echo "FROM nginx:stable" > Dockerfile
echo "EXPOSE 443" >> Dockerfile

# Source directory containing the vulnerability-db files
source_dir="$PWD"

# Destination directory in the Docker container
dest_dir="/usr/share/nginx/html/"

# Loop through each file and generate COPY commands
for file in "$source_dir"/vulnerability-db*.tar.gz; do
    # Get the filename without the path
    filename=$(basename -- "$file")
    # Generate the COPY command
    echo "COPY ./$filename $dest_dir$filename" >> Dockerfile
done

echo "STOPSIGNAL SIGQUIT" >> Dockerfile
echo 'CMD ["nginx", "-g", "daemon off;"]' >> Dockerfile

docker login $PUSH_REGISTRY_FQDN -u $PUSH_REGISTRY_USERNAME -p $PUSH_REGISTRY_PASSWORD
docker buildx build --push --platform linux/amd64 -t "$PUSH_REGISTRY_WITH_PROJECT/grype:latest" . 
docker pull "$PUSH_REGISTRY_WITH_PROJECT/grype:latest"
docker save -o grype-with-db.tar "$PUSH_REGISTRY_WITH_PROJECT/grype:latest"

rm -f httpproxy.yaml || true
rm -f grype-airgap-overlay.yaml || true
rm -f flow.txt || true

cat <<EOT >> flow.txt
In the airgapped environment, run:

kubectl create deployment grype --image=<grype-image-in-internal-registry> --replicas=2
kubectl expose deployment grype --type=ClusterIP --port 8080 --target-port 80
kubectl apply -f httpproxy.yaml

kubectl config use-context <tap-cluster>

kubectl apply -f grype-airgap-overlay.yaml

in tap-values, include:

package_overlays:
 - name: "grype"
   secrets:
      - name: "grype-airgap-overlay"
EOT

cd ..

echo ""
echo "Downloading IDE Plugins"
echo "-----------------------"
mkdir -p ide-plugins

$PIVNET product-files -p 'tanzu-application-platform' -r $TAP_VERSION --format json > slugs.json
$PIVNET download-product-files -p 'tanzu-application-platform' -r $TAP_VERSION -d ide-plugins --product-file-id $($JQ_CLI '.[] | select(.name == "Tanzu Developer Tools for Visual Studio") | .id' slugs.json)
$PIVNET download-product-files -p 'tanzu-application-platform' -r $TAP_VERSION -d ide-plugins --product-file-id $($JQ_CLI '.[] | select(.name == "Tanzu GitOps Reference Implementation") | .id' slugs.json)
$PIVNET download-product-files -p 'tanzu-application-platform' -r $TAP_VERSION -d ide-plugins --product-file-id $($JQ_CLI '.[] | select(.name == "Tanzu App Accelerator Extension for Intellij") | .id' slugs.json)
$PIVNET download-product-files -p 'tanzu-application-platform' -r $TAP_VERSION -d ide-plugins --product-file-id $($JQ_CLI '.[] | select(.name == "Tanzu App Accelerator Extension for Visual Studio Code") | .id' slugs.json)
$PIVNET download-product-files -p 'tanzu-application-platform' -r $TAP_VERSION -d ide-plugins --product-file-id $($JQ_CLI '.[] | select(.name == "Tanzu Developer Tools for Visual Studio Code") | .id' slugs.json)
$PIVNET download-product-files -p 'tanzu-application-platform' -r $TAP_VERSION -d ide-plugins --product-file-id $($JQ_CLI '.[] | select(.name == "Tanzu Developer Tools for Intellij") | .id' slugs.json)
$PIVNET download-product-files -p 'tanzu-application-platform' -r $TAP_VERSION -d ide-plugins --product-file-id $($JQ_CLI '.[] | select(.name == "Tanzu Application Platform Developer Portal Blank Catalog") | .id' slugs.json)
$PIVNET download-product-files -p 'tanzu-application-platform' -r $TAP_VERSION -d ide-plugins --product-file-id $($JQ_CLI '.[] | select(.name == "Tanzu Application Platform Developer Portal Yelb Catalog") | .id' slugs.json)

rm slugs.txt
rm slugs.json

echo ""
echo "Downloading documentation PDF"
echo "-----------------------------"

export TAP_MAJOR_VERSION=${TAP_VERSION%.*}
export CLUSTER_ESSENTIALS_MAJOR_VERSION=${CLUSTER_ESSENTIALS_VERSION%.*}
wget -U "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" "https://docs.vmware.com/en/VMware-Tanzu-Application-Platform/$TAP_MAJOR_VERSION/tap.pdf"
wget -U "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" "https://docs.vmware.com/en/Cluster-Essentials-for-VMware-Tanzu/$CLUSTER_ESSENTIALS_MAJOR_VERSION/cluster-essentials/deploy.html"

echo ""
echo "Downloading TILT"
echo "----------------"

mkdir -p tilt

wget -P tilt "https://github.com/tilt-dev/tilt/releases/download/v$TILT_VERSION/tilt.$TILT_VERSION.linux.x86_64.tar.gz"
wget -P tilt "https://github.com/tilt-dev/tilt/releases/download/v$TILT_VERSION/tilt.$TILT_VERSION.mac.arm64.tar.gz"
wget -P tilt "https://github.com/tilt-dev/tilt/releases/download/v$TILT_VERSION/tilt.$TILT_VERSION.mac.x86_64.tar.gz"
wget -P tilt "https://github.com/tilt-dev/tilt/releases/download/v$TILT_VERSION/tilt.$TILT_VERSION.windows.x86_64.zip"

echo ""
echo "Folder is created! Creating tarball"
echo "-----------------------------------"

tar -czf ~/tap-airgapped-install-$TAP_VERSION.tar.gz .

echo ""
echo "Tarball is available at ~/tap-airgapped-install-$TAP_VERSION.tar.gz"
echo "--------------------------------------------------"


echo ""
echo "All done! Happy airgapping"
echo "Contact my at @odedia"
echo "--------------------------"




