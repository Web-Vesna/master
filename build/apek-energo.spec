%define homepath /usr/local/apek-energo
%define confpath %{homepath}/etc
%define repodir repo
%define branch_name apek-energo-test
%define service_path /usr/lib/systemd/system/
%define initscript %{confpath}/initscript

%define __g_version 1.2
%define __g_release %(date +"%Y%m%d%H%M")

Name:		apek-energo
License:	Redistributable, no modification permitted
Version:	%{__g_version}
Release:	%{__g_release}
Summary:	Apek-Energo project
Group:		Applications/Multimedia
Url:		https://github.com/Web-Vesna/master
Packager:	Pavel Berezhnoy <p.berezhnoy@web-vesna.ru>
BuildRoot:	%{_tmppath}/%{name}-root
BuildArch:	noarch

%description

%package common

Summary:	Apek-Energo common libraries
Version:	%{__g_version}
Release:	%{__g_release}
Group:		Applications/Multimedia
BuildArch:	noarch

Provides:	perl(AccessDispatcher)
Provides:	perl(DB)
Provides:	perl(MainConfig)
Provides:	perl(Translation)

Requires(pre): shadow-utils

%description common

Common Apek-Energo scripts, used by all daemons

%package data

Summary:	Apek-Energo data daemon
Version:	%{__g_version}
Release:	%{__g_release}
Group:		Applications/Multimedia
BuildArch:	noarch

Requires:	%{name}-common = %{version}-%{release}

%description data

Daemon works with database engine and provides an access to low-level logic.

%package front

Summary:	Apek-Energo frontend daemon
Version:	%{__g_version}
Release:	%{__g_release}
Group:		Applications/Multimedia
BuildArch:	noarch

Requires:	%{name}-common = %{version}-%{release}

%description front

Apek-Energo project frontend part

%package session

Summary:	Apek-Energo session daemon
Version:	%{__g_version}
Release:	%{__g_release}
Group:		Applications/Multimedia
BuildArch:	noarch

Requires:	%{name}-common = %{version}-%{release}

%description session

Daemon enables a session mechanism for Apek-Energo project

%package logic

Summary:	Apek-Energo proxy daemon
Version:	%{__g_version}
Release:	%{__g_release}
Group:		Applications/Multimedia
BuildArch:	noarch

Requires:	%{name}-common = %{version}-%{release}

%description logic 

Daemon implements a proxy between frontend and data

%package files

Summary:	Apek-Energo files daemon
Version:	%{__g_version}
Release:	%{__g_release}
Group:		Applications/Multimedia
BuildArch:	noarch

Requires:	%{name}-common = %{version}-%{release}

%description files

Daemon implements a files interface for Apek-Energo project

%prep

%define buildroot_impl %{buildroot}/%{homepath}
git clone https://github.com/Web-Vesna/master %{repodir}
cd %{repodir}
git checkout origin/%{branch_name}

mkdir -p %{buildroot}/%{confpath}
mkdir -p %{buildroot}/%{_initddir}
mkdir -p %{buildroot}/tmp
mkdir -p %{buildroot}/%{service_path}

cp build/%{name}.conf %{buildroot}/%{confpath}
cp build/nginx.conf %{buildroot}/%{confpath}
cp build/initscript %{buildroot}/%{initscript}
cp translation %{buildroot}/%{confpath}/%{name}.translate

# Generate a files list for any package
# and copy them into required pathes
for prj in 'data' 'front' 'session' 'logic' 'files' 'lib'; do
	find $prj -type f \( -name '*.pl' -o -name '*.pm' -o -name "$prj" -o -name '*.js' -o -name '*.ep' \
		-o -name '*.htc' -o -name '*.php' -o -name '*.png' -o -name '*.jpg' -o -name '*.gif' -o -name 'icons.woff2' \
		-o -name 'Thumbs.db' -o -name '*.css' \) > $prj.files

	cat $prj.files | xargs -I @ dirname @ | xargs -I @@ mkdir -p %{buildroot_impl}/@@
	cat $prj.files | xargs -I @ cp @ %{buildroot_impl}/@
	cat $prj.files | awk '{print "/%{homepath}/"$1}' > %{_builddir}/$prj.files

	if [ "$prj" != "lib" ]; then
		cp build/apek-energo.service %{buildroot}/tmp/service
		perl -pe "s/__INSTANCE_NAME__/$prj/; s#__INIT_SCRIPT__#%{initscript}#" %{buildroot}/tmp/service
		mv %{buildroot}/tmp/service %{buildroot}/%{service_path}/%{name}-$prj.service
		cp build/post_inst.sh %{buildroot}/tmp/%{name}-%{release}-$prj.sh

		echo "%{initscript}" >> %{_builddir}/$prj.files
		echo "%{service_path}/%{name}-$prj.sh" >> %{_builddir}/$prj.files
	fi
done

%clean

rm -rf %{_builddir}/%{repodir}

%files common -f lib.files

%defattr(644, %{name}, %{name}, -)
%config(noreplace) %{confpath}/%{name}.conf
%config(noreplace) %{confpath}/nginx.conf

%config %{confpath}/%{name}.translate

%files data -f data.files

%defattr(644, %{name}, %{name}, -)
%attr(755,root,root) %{_initddir}/%{name}-data
%attr(755,root,root) /tmp/%{name}-%{release}-data.sh

%files front -f front.files

%defattr(644, %{name}, %{name}, -)
%attr(755,root,root) %{_initddir}/%{name}-front
%attr(755,root,root) /tmp/%{name}-%{release}-front.sh

%files session -f session.files

%defattr(644, %{name}, %{name}, -)
%attr(755,root,root) %{_initddir}/%{name}-session
%attr(755,root,root) /tmp/%{name}-%{release}-session.sh

%files logic -f logic.files

%defattr(644, %{name}, %{name}, -)
%attr(755,root,root) %{_initddir}/%{name}-logic
%attr(755,root,root) /tmp/%{name}-%{release}-logic.sh

%files files -f files.files

%defattr(644, %{name}, %{name}, -)
%attr(755,root,root) %{_initddir}/%{name}-files
%attr(755,root,root) /tmp/%{name}-%{release}-files.sh

%pre common

getent group %{name} >/dev/null || groupadd -r %{name}
getent passwd %{name} >/dev/null || \
    useradd -r -g %{name} -d %{homepath} -s /sbin/nologin  %{name}
exit 0

%post data

/tmp/%{name}-%{release}-data.sh %{homepath} %{name} data
rm -f /tmp/%{name}-%{release}-data.sh

%post front

/tmp/%{name}-%{release}-front.sh %{homepath} %{name} front
rm -f /tmp/%{name}-%{release}-front.sh

%post session

/tmp/%{name}-%{release}-session.sh %{homepath} %{name} session
rm -f /tmp/%{name}-%{release}-session.sh

%post logic

/tmp/%{name}-%{release}-logic.sh %{homepath} %{name} logic
rm -f /tmp/%{name}-%{release}-logic.sh

%post files

/tmp/%{name}-%{release}-files.sh %{homepath} %{name} files
rm -f /tmp/%{name}-%{release}-files.sh
