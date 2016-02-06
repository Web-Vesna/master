%define homepath %{_libdir}/apek-energo

Name:		apek-energo
License:	Redistributable, no modification permitted
Version:	1
Release:	2
Summary:	Apek-Energo project
Group:		Applications/Multimedia
Url:		https://github.com/Web-Vesna/master
Packager:	Pavel Berezhnoy <p.berezhnoy@web-vesna.ru>
BuildRoot:	%{_tmppath}/%{name}-root
BuildArch:	noarch

# epel and magnum repos are required here
Requires:	perl(Mojolicious)

%description

Nothing interesting

XXX: perl-Mojolicious can be installed via cpan

%package common

Summary:	Apek-Energo common libraries
Version:	1
Release:	1
Group:		Applications/Multimedia
BuildArch:	noarch

%description common

Common Apek-Energo scripts, used by all daemons

%package data

Summary:	Apek-Energo data daemon
Version:	1
Release:	1
Group:		Applications/Multimedia
BuildArch:	noarch

%description data

Daemon works with database engine and provides an access to low-level logic.

%package front

Summary:	Apek-Energo frontend daemon
Version:	1
Release:	1
Group:		Applications/Multimedia
BuildArch:	noarch

%description front

Apek-Energo project frontend part

%package session

Summary:	Apek-Energo session daemon
Version:	1
Release:	1
Group:		Applications/Multimedia
BuildArch:	noarch

%description session

Daemon enables a session mechanism for Apek-Energo project

%package logic

Summary:	Apek-Energo proxy daemon
Version:	1
Release:	1
Group:		Applications/Multimedia
BuildArch:	noarch

%description logic 

Daemon implements a proxy between frontend and data

%package files

Summary:	Apek-Energo files daemon
Version:	1
Release:	1
Group:		Applications/Multimedia
BuildArch:	noarch

%description files

Daemon implements a files interface for Apek-Energo project

#################

%prep

%define repodir repo
%define buildroot_impl %{buildroot}/%{homepath}
git clone https://github.com/Web-Vesna/master %{repodir}
cd %{repodir}
git checkout origin/apek-energo

# Generate a files list for any package
for prj in 'data' 'front' 'session' 'logic' 'files' 'lib'; do
	find $prj -type f \( -name '*.pl' -o -name '*.pm' -o -name "$prj" -o -name '*.js' -o -name '*.ep' \
		-o -name '*.htc' -o -name '*.php' -o -name '*.png' -o -name '*.jpg' -o -name '*.gif' -o -name 'icons.woff2' \
		-o -name 'Thumbs.db' -o -name '*.css' \) > $prj.files

	cat $prj.files | xargs -I @ dirname @ | xargs -I @@ mkdir -p %{buildroot_impl}/@@
	cat $prj.files | xargs -I @ cp @ %{buildroot_impl}/@
	cat $prj.files | awk '{print "/%{homepath}/"$1}' > %{_builddir}/$prj.files
done

#################

%clean

rm -rf %{_builddir}/master

%files common -f lib.files

%files data -f data.files

%files front -f front.files

%files session -f session.files

%files logic -f logic.files

%files files -f files.files


