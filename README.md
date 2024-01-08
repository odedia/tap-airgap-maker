TAP Airgap maker

This script will generate a tarball that you can move to an airgapped environment with (hopefully) all required clis, dependencies and plugins.

This script should work well for both linux and macOS.

This script should work well for both linux and macOS.

The script downloads and generates the following dependencies:
- Pivnet CLI
- Tanzu CLI for all platforms
- Tanzu CLI plugins as tarball for airgapped installation
- Cluster essentials for all platforms
- Cluster essentials image dependencies (with imgpkg)
- TAP image dependencies (with imgpkg)
- Build Service full dependencies
- Grype with a working vulnerabilities database for airgapped environments
- IDE plugins for Visual Studio, VS Code and InteliJ
- Documentation as PDF
- Tilt

Before running the script, create a file in the following path:

```
~/.tap/tap-secrets
```

The contents should be as follows:

```
PIVNET_VERSION=4.1.1
PIVNET_TOKEN=<Get one at https://network.pivotal.io/users/dashboard/edit-profile>
TAP_VERSION=1.7.2
CLUSTER_ESSENTIALS_VERSION=1.7.2
IMGPKG_REGISTRY_USERNAME=<enter your Tanzu Network username as email>
IMGPKG_REGISTRY_PASSWORD=<enter your Tanzu Network password>
PUSH_REGISTRY_WITH_PROJECT=<Format is my.example.registry.com/apps. Used for grype image creation, access to registry is only needed outside of airgapped environment. >
GRYPE_FQDN=<FQDN that will eventually host the grype DB in the airgapped environment, such as grype.myintranet.local. You can set a dummy value here and edit the files manually in the airgapped environment>
TILT_VERSION=0.33.10
```

To create the tarball:

```
./airgapme.sh
```
