# TAP Airgap Maker

This repo will generate a tarball with Tanzu Application Platform that you can move to an airgapped environment with (hopefully) all required clis, dependencies and plugins.
It will also allow you to run a script inside the airgapped environment to prepare everything for installation.

Disclaimer: for educational purposes only, not a supported Tanzu solution.

## Airgapping Script

This script should work well for both linux and macOS (Intel and Apple Silicon).

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
PUSH_REGISTRY_WITH_PROJECT=<See explanation below>
GRYPE_FQDN=<See explanation below>
TILT_VERSION=0.33.10
```
`PUSH_REGISTRY_WITH_PROJECT` is simply any docker registry that can temporarily host a docker image, it can even be dockerhub. We just need this because the script can run on M1 Macs, so we much build with the `docker buildx` command that for some reason fails to output a working docker image as a tarball (at least on my machine). So, the alternative is to push the image to a registry and then pull it locally again. Ofcourse - access to the registry is *not* needed inside of airgapped environment.
GRYPE_FQDN is the FQDN that will eventually host the grype DB server inside the airgapped environment, such as grype.myintranet.local. If that URL is sensitive, you can set a dummy value here and edit the files manually in the airgapped environment, but that means you'll have to also rebuild the image inside the intranet, which means tweaking the Dockerfile a bit.

To create the tarball:

```
./airgapme.sh
```

## Running in the airgapped environment

After you somehow moved the tarball to your airgapped environment, you can prepare all that's needed to have a working TAP installation.
The airgapped install is *only* for Linux VMs since that's 99% of the use cases.
The script should run as root.

Before running the script in the airgapped environment, create a file in the following path:

```
~/.tap/tap-secrets
```

The contents should be as follows:
```
#Required in internal tap-secrets
TAP_VERSION=1.7.2
GRYPE_FQDN=<The FQDN that will host the grype DB server on the cluster>
INTERNAL_REGISTRY_FQDN=<such as myinternaljfrog.local>
INTERNAL_REGISTRY_WITH_PROJECT=<myinternaljfrog.local/tap>
INTERNAL_REGISTRY_USERNAME=<the registry username>
INTERNAL_REGISTRY_PASSWORD=<the registry password>
INTERNAL_REGISTRY_PATH_TO_CERT=<The full path to a registry's self signed certificate on the machine, such as /root/registry.crt>
```

Then, simply run:

```
./fillthegap.sh ~/tap-airgapped-install-1.7.2.tar.gz
```

The script will all required clis, upload all required packages to the internal registry, and create a `flow.txt` that will give you a step by step instructions to install TAP in your environment with your internal registry values.

Feedback and pull requests are welcome.

