#!/bin/bash
set -x

SCRIPTDIR=$(dirname -- "$( readlink -f -- "$0"; )")
[ -z "$DESTDIR" ] && DESTDIR=$SCRIPTDIR/../artifacts

RPM_RELEASE=1
TAG_EXACT=$(git describe --exact-match --abbrev=0 --tags)
TAG_NEAR=$(git describe --abbrev=0 --tags)
COMMIT_TAG=$(git rev-parse --short HEAD)

if [ -z $TAG_EXACT ]; then 
  VERSION=$TAG_NEAR
  COMMIT_TAG=${COMMIT_TAG}
else
  VERSION=$TAG_EXACT
  COMMIT_TAG=
fi

[ -z "$COMMIT_TAG" ]  && sed -i -e "s|^VERSION=.*|VERSION=$VERSION|g" $SCRIPTDIR/../src/nx3all.bash
[ ! -z "$COMMIT_TAG" ]  && sed -i -e "s|^VERSION=.*|VERSION=$VERSION-$COMMIT_TAG|g" $SCRIPTDIR/../src/nx3all.bash

cat $SCRIPTDIR/../src/nx3all.bash | grep VERSION

DESTDIR=$(readlink -f "${DESTDIR}")
TARDIR="${DESTDIR}/nx3all-${VERSION}"

mkdir -p ${TARDIR}

# generate binary
#cat ${SCRIPTDIR}/script.sh > ${TARDIR}/nx3all
#base64 ${SCRIPTDIR}/../src/nx3all.bash >> ${TARDIR}/nx3all
cp ${SCRIPTDIR}/../src/nx3all.bash ${TARDIR}/nx3all
chmod +x ${TARDIR}/nx3all

# generate footprint
cd ${TARDIR}
sha256sum nx3all > nx3all.sha256.txt

# generate archive
cd ${DESTDIR}
tar czvf nx3all-${VERSION}-${RPM_RELEASE}${COMMIT_TAG}.tar.gz nx3all-${VERSION}

# generate rpm
mkdir -p ~/rpmbuild/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
cp nx3all-${VERSION}-${RPM_RELEASE}${COMMIT_TAG}.tar.gz ~/rpmbuild/SOURCES

if [ -z $TAG_EXACT ]; then 
  rpmbuild --target noarch  --define "VERSION ${VERSION}" --define "RPM_RELEASE ${RPM_RELEASE}" --define "COMMIT_TAG ${COMMIT_TAG}" -bb ${SCRIPTDIR}/../packages/nx3all.spec
else
  rpmbuild --target noarch  --define "VERSION ${VERSION}" --define "RPM_RELEASE ${RPM_RELEASE}"  -bb ${SCRIPTDIR}/../packages/nx3all.spec
fi
cp -v ~/rpmbuild/RPMS/noarch/*.rpm ${DESTDIR}

# generate deb
mkdir -p $DESTDIR/deb/nx3all/usr/local/bin $DESTDIR/deb/nx3all/DEBIAN
cp -v ${TARDIR}/* $DESTDIR/deb/nx3all/usr/local/bin
cat <<EOF > $DESTDIR/deb/nx3all/DEBIAN/control
Package: nx3all
Version: ${VERSION}-${RPM_RELEASE}${COMMIT_TAG}
Maintainer: extempis
Architecture: all
Description: Tools for backup and restore nexus 3 repository
EOF

cd $DESTDIR/deb/
dpkg-deb --build nx3all
mv nx3all.deb $DESTDIR/nx3all-${VERSION}-${RPM_RELEASE}${COMMIT_TAG}.deb

cd ${DESTDIR}

# generate footprints
sha256sum nx3all-${VERSION}-${RPM_RELEASE}${COMMIT_TAG}.tar.gz > nx3all-${VERSION}-${RPM_RELEASE}${COMMIT_TAG}.tar.gz.sha256.txt
sha256sum nx3all-${VERSION}-*.rpm > nx3all-${VERSION}-${RPM_RELEASE}${COMMIT_TAG}.noarch.rpm.sha256.txt
sha256sum nx3all-${VERSION}-${RPM_RELEASE}${COMMIT_TAG}.deb > nx3all-${VERSION}-${RPM_RELEASE}${COMMIT_TAG}.deb.sha256.txt

# Verify sha
sha256sum -c nx3all-*.txt