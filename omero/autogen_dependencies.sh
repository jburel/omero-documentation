#!/usr/bin/env bash
# This script is used by a Continuous Integration job to update
# the versions of the "ome" dependencies
# We have 3 groups:
#  - dependencies on artifactories e.g. omero-dsl-plugin
#  - dependencies on GitHub e.g. omero-insight
#  - dependencies on pypi e.g. omero-py
#  - openmicroscopy: 
#    - Find latest release from GitHub
#    - Download the latest zip
#    - check version of the dependencies

PREFIX="omero-"

# General java packages
# Java packages
dirs=("org/openmicroscopy/omero-dsl-plugin" "org/openmicroscopy/omero-blitz-plugin")
for dir in "${dirs[@]}"
    do
        : 
        values=(${dir//// })
        value=${values[${#values[@]}-1]}
        v=${value#"$PREFIX"}
        v=${v//"-"/"_"}
        echo $v
        # get the latest version of the package
        # Determine the latest release version on artifactory and update omero/conf_autogen.py
        repopath="https://artifacts.openmicroscopy.org/artifactory/ome.releases/${dir}"
        version=`curl -s ${repopath}/maven-metadata.xml | grep latest | sed "s/.*<latest>\([^<]*\)<\/latest>.*/\1/"`
        echo $version
        sed -i -e "s/version_${v} = .*/version_${v} = \"${version}\"/" omero/conf_autogen.py
    done

# GitHub packages
new_version=""
github_packages=("ome/openmicroscopy" "ome/omero-insight" "ome/omero-matlab")
for p in "${github_packages[@]}"
do
    :
    values=(${p//// })
    value=${values[${#values[@]}-1]}
    v=${value#"$PREFIX"}
    v=${v//"-"/"_"} 
    # Determine the latest release version on GittHub and update omero/conf_autogen.py
    version=`curl --silent "https://api.github.com/repos/$p/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'`
    # drop v or version
    version=${version//"v"/""}
    if [ $v = "openmicroscopy" ]; then
        while IFS= read -r line; do
           values=(${line/=/ })
           if [[ ${values[0]} = "version_openmicroscopy" && \"$version\" != ${values[1]} ]]; then
               new_version=$version
           fi
        done < omero/conf_autogen.py
    fi
    
    sed -i -e "s/version_${v} = .*/version_${v} = \"${version}\"/" omero/conf_autogen.py
done

echo $new_version

# Java packages

# the version of GitHub does not match the version in omero/conf_autogen.py
# Download the latest server release
# Unzip
# Determine the version of the dependencies
# Update omero/conf_autogen.py
if [ ! -z $new_version ]; then
    # Download the latest binary to make we have the correct one.
    # To be replaced by the GitHub url without build number when ready
    SERVER=https://downloads.openmicroscopy.org/omero/5.6/server-ice36.zip
    wget -q $SERVER -O OMERO.server-ice36.zip
    unzip -q OMERO.server*
    ln -s OMERO.server-*/ OMERO.server
    dirs=("OMERO.server/lib/server/omero-blitz.jar" "OMERO.server/lib/server/omero-server.jar" "OMERO.server/lib/server/omero-gateway.jar"
      "OMERO.server/lib/server/omero-romio.jar" "OMERO.server/lib/server/omero-renderer.jar" "OMERO.server/lib/server/omero-common.jar"
      "OMERO.server/lib/server/omero-model.jar" "OMERO.server/lib/server/formats-gpl.jar")
    for dir in "${dirs[@]}"
    do
        :
        values=(${dir//// })
        value=${values[${#values[@]}-1]}
        v=${value#"$PREFIX"}
        version=`unzip -p $dir META-INF/MANIFEST.MF | grep "Implementation-Version:" | sed 's/^.*[^0-9]\([0-9]*\.[0-9]*\.[0-9]*\).*$/\1/'`
        sed -i -e "s/version_${v} = .*/version_${v} = \"${version}\"/" omero/conf_autogen.py
        echo $v
        echo $version
    done
    # clean up 
    rm -rf OMERO.server*
fi


# Python packages
dirs=("omero-py" "omero-web" "omero-dropbox")
for package in "${dirs[@]}"
do
    :
    v=${package#"$PREFIX"}
    # Determine the latest release version on pypi and update omero/conf_autogen.py
    version=`curl -Ls https://pypi.org/pypi/$package/json | jq -r .info.version`
    sed -i -e "s/version_${v} = .*/version_${v} = \"${version}\"/" omero/conf_autogen.py
done



# Clean up
if [ -f omero/conf_autogen.py-e ]; then
    rm omero/conf_autogen.py-e
fi

