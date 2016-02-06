%define homepath %{_libdir}/apek-energo
%define repodir repo
%define branch_name apek-energo-test

%define __g_version 1.2
%define __g_release 1

Prefix:		/usr/local
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

%description common

Common Apek-Energo scripts, used by all daemons

Execute to install dependencies (via super user).
Force is not required, but some tests are failed and modules can't be installed from this.

$ cpan
 > force install Time::HiRes
 > force install Mojo::URL Mojo::UserAgent Mojo::Util Mojo::Base Mojo::JSON Mojolicious::Commands Mojo::Base Mojolicious::Commands Mojo::Base Mojolicious::Commands Mojo::Base Mojo::JSON Mojolicious::Commands Mojo::Base Mojolicious::Commands
 > force install Data::Dumper::OneLine
 > force install Excel::Writer::XLSX
 > force install Spreadsheet::ParseExcel
 > force install Spreadsheet::XLSX
 > force install URL::Encode::XS
 > force install Cache::Memcached
 > force install JSON

%package data

Summary:	Apek-Energo data daemon
Version:	%{__g_version}
Release:	%{__g_release}
Group:		Applications/Multimedia
BuildArch:	noarch

Requires:	mysql-server
Requires:	%{name}-common = %{version}-%{release}

%description data

Daemon works with database engine and provides an access to low-level logic.

%package front

Summary:	Apek-Energo frontend daemon
Version:	%{__g_version}
Release:	%{__g_release}
Group:		Applications/Multimedia
BuildArch:	noarch

Requires:	nginx
Requires:	%{name}-common = %{version}-%{release}
Requires:	%{name}-session = %{version}-%{release}
Requires:	%{name}-data = %{version}-%{release}

%description front

Apek-Energo project frontend part

%package session

Summary:	Apek-Energo session daemon
Version:	%{__g_version}
Release:	%{__g_release}
Group:		Applications/Multimedia
BuildArch:	noarch

Requires:	memcached
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
Requires:	%{name}-session = %{version}-%{release}
Requires:	%{name}-data = %{version}-%{release}

%description logic 

Daemon implements a proxy between frontend and data

%package files

Summary:	Apek-Energo files daemon
Version:	%{__g_version}
Release:	%{__g_release}
Group:		Applications/Multimedia
BuildArch:	noarch

Requires:	memcached
Requires:	%{name}-session = %{version}-%{release}

%description files

Daemon implements a files interface for Apek-Energo project

%prep

%define buildroot_impl %{buildroot}/%{homepath}
git clone https://github.com/Web-Vesna/master %{repodir}
cd %{repodir}
git checkout origin/%{branch_name}

# Generate a files list for any package
# and copy them into required pathes
for prj in 'data' 'front' 'session' 'logic' 'files' 'lib'; do
	find $prj -type f \( -name '*.pl' -o -name '*.pm' -o -name "$prj" -o -name '*.js' -o -name '*.ep' \
		-o -name '*.htc' -o -name '*.php' -o -name '*.png' -o -name '*.jpg' -o -name '*.gif' -o -name 'icons.woff2' \
		-o -name 'Thumbs.db' -o -name '*.css' \) > $prj.files

	cat $prj.files | xargs -I @ dirname @ | xargs -I @@ mkdir -p %{buildroot_impl}/@@
	cat $prj.files | xargs -I @ cp @ %{buildroot_impl}/@
	cat $prj.files | awk '{print "/%{homepath}/"$1}' > %{_builddir}/$prj.files
done

mkdir -p %{_builddir}/%{_sysconfdir}
cp build/%{name}.conf %{_builddir}/%{_sysconfdir}

%clean

rm -rf %{_builddir}/%{repodir}

%files common -f lib.files

%config(noreplace) %{_sysconfdir}/%{name}.conf

%files data -f data.files

%files front -f front.files

%files session -f session.files

%files logic -f logic.files

%files files -f files.files


