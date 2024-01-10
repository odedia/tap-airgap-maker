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

# Check if the parameter is provided
if [ $# -eq 0 ]; then
    echo "Please provide the tar.gz as parameter to the script. Exiting."
    exit 1
else
    # If provided, use the provided parameter
    tarball=$1
fi

# Use the param variable for further operations
echo "Parameter provided: $param"

docker login $INTERNAL_REGISTRY_FQDN -u $INTERNAL_REGISTRY_USERNAME -p $INTERNAL_REGISTRY_PASSWORD
mkdir -p workspace

tar -xvf $tarball -C workspace

if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    export JQ_CLI="jq/jq-linux-amd64"
else
    echo "Unsupported OS"
    exit 1
fi

echo "" > instructions.txt
mkdir -p workspace/tanzu-cli
tar -xvf workspace/all-tanzu-clis/tanzu-cli-linux-amd64.tar.gz -C workspace/tanzu-cli

mkdir -p workspace/tanzu-cli-tmp
find workspace/tanzu-cli -type f -name "tanzu-cli*" -exec mv {} workspace/tanzu-cli-tmp/ \;
rm -rf workspace/tanzu-cli/v*
mv workspace/tanzu-cli-tmp/* /usr/local/bin/tanzu
rm -rf workspace/tanzu-cli-tmp
chmod +x /usr/local/bin/tanzu

echo ""
echo "Installing Tanzu CLI Plugins"
echo "-----------------------------"

tanzu config cert add --host $INTERNAL_REGISTRY_FQDN --ca-certificate $INTERNAL_REGISTRY_PATH_TO_CERT
tanzu plugin upload-bundle --tar workspace/tanzu-cli/plugins.tar --to-repo $INTERNAL_REGISTRY_WITH_PROJECT/plugin


echo ""
echo "Moving cluster essentials binaries to /usr/local/bin/"
echo "-----------------------------------"

rm -rf /tmp/cluster-essentials-tmp
mkdir -p /tmp/cluster-essentials-tmp
tar -xvf "all-cluster-essentials/tanzu-cluster-essentials-linux-amd64-$TAP_VERSION.tgz" -C /tmp/cluster-essentials-tmp
mv /tmp/cluster-essentials-tmp/imgpkg /usr/local/bin/imgpkg
mv /tmp/cluster-essentials-tmp/kbld /usr/local/bin/kbld
mv /tmp/cluster-essentials-tmp/kapp /usr/local/bin/kapp
mv /tmp/cluster-essentials-tmp/ytt /usr/local/bin/ytt

echo ""
echo "Uploading cluster-essentials images"
echo "-----------------------------------"


export IMGPKG_REGISTRY_HOSTNAME=$INTERNAL_REGISTRY_FQDN 
export IMGPKG_REGISTRY_USERNAME=$INTERNAL_REGISTRY_USERNAME 
export IMGPKG_REGISTRY_PASSWORD=$INTERNAL_REGISTRY_PASSWORD 

./imgpkg copy \
    --tar all-cluster-essentials/cluster-essentials-bundle.tar \
    --to-repo $INTERNAL_REGISTRY_WITH_PROJECT/cluster-essentials-bundle \
    --include-non-distributable-layers \
    --registry-ca-cert-path $INTERNAL_REGISTRY_PATH_TO_CERT

sha256_hash=$(<all-cluster-essentials/sha256_hash.txt)

echo "" >flow.txt

cat <<EOT >> step1.txt

To install Cluster Essentials on a cluster, make sure you point to the cluster with kubectl, then copy-paste the following command:

INSTALL_BUNDLE=$INTERNAL_REGISTRY_WITH_PROJECT/$sha256_hash \
  INSTALL_REGISTRY_HOSTNAME=$INTERNAL_REGISTRY_FQDN \
  INSTALL_REGISTRY_USERNAME=$INTERNAL_REGISTRY_USERNAME \
  INSTALL_REGISTRY_PASSWORD=$INTERNAL_REGISTRY_PASSWORD \
  ./install.sh

EOT

echo ""
echo "Uploading TAP Package images"
echo "-----------------------------"

imgpkg copy \
  --tar tap-dependencies/tap-packages-$TAP_VERSION.tar \
  --to-repo $INTERNAL_REGISTRY_WITH_PROJECT/tap-packages \
  --include-non-distributable-layers \
  --registry-ca-cert-path $INTERNAL_REGISTRY_PATH_TO_CERT


cat <<EOT >> step2.txt

Create the tap-install namespace:

kubectl create ns tap-install

Create the TAP registry secret:

tanzu secret registry add tap-registry \
    --server   $INTERNAL_REGISTRY_FQDN \
    --username $INTERNAL_REGISTRY_USERNAME \
    --password $INTERNAL_REGISTRY_PASSWORD \
    --namespace tap-install \
    --export-to-all-namespaces \
    --yes

Create the User registry (It's the same credentials but they don't have to be in some scenarios):

tanzu secret registry add registry-credentials \
    --server   $INTERNAL_REGISTRY_FQDN \
    --username $INTERNAL_REGISTRY_USERNAME \
    --password $INTERNAL_REGISTRY_PASSWORD \
    --namespace tap-install \
    --export-to-all-namespaces \
    --yes

Add the package repository:

tanzu package repository add tanzu-tap-repository \
  --url $INTERNAL_REGISTRY_FQDN/tap-packages:$TAP_VERSION \
  --namespace tap-install

Continue setting up the tap-values.yaml as per documentation. A sample yaml is in the available at tap-dependencies/sample-tap-values.yaml
When you're ready, install TAP with this command:

tanzu package install tap -p tap.tanzu.vmware.com -v $TAP_VERSION --values-file tap-values.yaml -n tap-install
EOT

echo ""
echo "Uploading Build Service Package images"
echo "--------------------------------------"

imgpkg copy --tar tap-dependencies/full-deps-package-repo.tar \
  --to-repo=$INTERNAL_REGISTRY_WITH_PROJECT/full-deps-package-repo


cat <<EOT >> step3.txt

Add the full dependencies package repo:

tanzu package repository add full-deps-package-repo \
  --url $INTERNAL_REGISTRY_WITH_PROJECT/full-deps-package-repo:$TAP_VERSION \
  --namespace tap-install

Then install the dependencies:

tanzu package install full-deps -p full-deps.buildservice.tanzu.vmware.com -v "> 0.0.0" -n tap-install

EOT

echo ""
echo "Uploading Grype DB"
echo "------------------"

docker load -i grype-with-db.tar
docker tag $PUSH_REGISTRY_WITH_PROJECT/grype:latest $INTERNAL_REGISTRY_WITH_PROJECT/grype:latest
docker push $INTERNAL_REGISTRY_WITH_PROJECT/grype:latest


cat <<EOT >> grype_httpproxy.yaml
apiVersion: projectcontour.io/v1
kind: HTTPProxy
metadata:
  name: grype-ingress
spec:
  virtualhost:
    fqdn: $GRYPE_FQDN
  routes:
    - services:
        - name: grype
          port: 8080
EOT

cat <<EOT >> grype-airgap-overlay.yaml
apiVersion: v1
kind: Secret
metadata:
  name: grype-airgap-overlay
  namespace: tap-install #! namespace where tap is installed
stringData:
  patch.yaml: |
    #@ load("@ytt:overlay", "overlay")

    #@overlay/match by=overlay.subset({"kind":"ScanTemplate","metadata":{"namespace":"demos"}}),expects="1+"
    #! developer namespace you are using
    ---
    spec:
      template:
        initContainers:
          #@overlay/match by=overlay.subset({"name": "scan-plugin"}), expects="0+"
          - name: scan-plugin
            #@overlay/match missing_ok=True
            env:
              #@overlay/append
              - name: GRYPE_CHECK_FOR_APP_UPDATE
                value: "false"
              - name: GRYPE_DB_AUTO_UPDATE
                value: "false"
              - name: GRYPE_DB_UPDATE_URL
                value: http://$GRYPE_FQDN/listing.json
              - name: GRYPE_DB_MAX_ALLOWED_BUILT_AGE #! see note on best practices
                value: "8760h"
EOT


cat <<EOT >> step4.txt
Run the following command to create the grype deployment on the cluster:

kubectl create deployment grype --image=$INTERNAL_REGISTRY_WITH_PROJECT/grype:latest --replicas=3
kubectl expose deployment grype --type=ClusterIP --port 8080 --target-port 80
kubectl apply -f grype_httpproxy.yaml
kubectl apply -f grype-airgap-overlay.yaml

In your tap-values.yaml, add the following section:

in tap-values, include:

package_overlays:
 - name: "grype"
   secrets:
      - name: "grype-airgap-overlay"
EOT

