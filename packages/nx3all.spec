Name:       nx3all
Version:    %{VERSION}
Release:    %{RPM_RELEASE}%{?COMMIT_TAG}
Summary:    Tools for backup and restore nexus 3 repository
Packager:   exTempis

License:    Apache 2.0
URL:        https://github.com/extempis/nx3all
BuildArch:  noarch

Requires: bash
Requires: coreutils
Requires: curl
Requires: jq

Source: %{name}-%{VERSION}-%{RPM_RELEASE}%{?COMMIT_TAG}.tar.gz

%description
Tools for backup and restore nexus 3 repository

%prep
%autosetup
mkdir -p $RPM_BUILD_ROOT/usr/local/bin
install -m755 $RPM_BUILD_DIR/%{name}-%{VERSION}/nx3all $RPM_BUILD_ROOT/usr/local/bin

%files
%attr(755, root, root) /usr/local/bin/nx3all

%changelog
* Sat Aug 27 2022 extempis <112153152+extempis@users.noreply.github.com>
- 

# Build with the following syntax:
# rpmbuild --target noarch -bb nx3all.spec
#https://opensource.com/article/18/9/how-build-rpm-packages
